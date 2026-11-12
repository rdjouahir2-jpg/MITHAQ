import { useCallback, useEffect, useMemo, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import {
  CarFront, CircleHelp, LogOut,
  MapPin, Navigation, RefreshCw, ShieldCheck, UserRound, Wallet,
} from 'lucide-react'
import MapPicker, { type GeoPoint } from './components/MapPicker'
import { isSupabaseConfigured, supabase } from './lib/supabase'
import { isNativeAndroid, refreshDriverBackgroundTrackingToken, startDriverBackgroundTracking, stopDriverBackgroundTracking } from './lib/backgroundLocation'
import { createFareQuote, recordDriverLocation, requestRide, setDriverAvailability } from './lib/rideApi'
import { getMyFareNegotiations, respondFareNegotiation, startFareNegotiation, type FareNegotiation } from './lib/fareNegotiationApi'

type Profile = { id: string; display_name: string; account_status: string }
type DriverProfile = { id: string; onboarding_status: string; availability_status: string }
type Ride = {
  id: string
  pickup_label: string
  destination_label: string
  category: string
  status: string
  quoted_amount_minor: number
  currency_code: string
  requested_at: string
  driver_id: string | null
  driver_name?: string | null
  vehicle_make?: string | null
  vehicle_model?: string | null
  vehicle_color?: string | null
  vehicle_seat_capacity?: number | null
  passenger_name?: string | null
}
type Offer = {
  offer_id: string
  ride_id: string
  pickup_label: string
  destination_label: string
  pickup_latitude: number
  pickup_longitude: number
  category: string
  proposed_amount_minor: number
  currency_code: string
  expires_at: string
}
type AdminAccount = { user_id: string; display_name: string; created_at: string }
type AdminRide = { ride_id: string; passenger_name: string; driver_name: string | null; pickup_label: string; destination_label: string; ride_status: string; quoted_amount_minor: number; currency_code: string; requested_at: string; completed_at: string | null }
type SafetyReport = { report_id: string; ride_id: string | null; reporter_name: string; category: string; severity: string; description: string; report_status: string; created_at: string }
type SupportTicket = { id: string; category: string; message: string; status: string; created_at: string; updated_at: string }
type SupportMessage = { id: string; ticket_id: string; body: string; is_staff: boolean; created_at: string }
type UserNotification = { id: string; notification_type: string; title: string; body: string; created_at: string; read_at: string | null }
type AdminSupportTicket = { ticket_id: string; user_id: string; requester_name: string; ride_id: string | null; category: string; initial_message: string; ticket_status: string; assigned_to: string | null; created_at: string; updated_at: string }
type RatingStatus = { has_rated: boolean; score: number | null; comment: string | null }
type DriverEarning = { ride_id: string; pickup_label: string; destination_label: string; completed_at: string; gross_fare_minor: number; commission_minor: number; driver_net_minor: number; payment_status: string; commission_status: string; currency_code: string }
type DriverFinancialSummary = { gross_earned_minor: number; commission_due_minor: number; payout_available_minor: number; payout_pending_minor: number; currency_code: string }
type AdminFinancial = { ride_id: string; driver_id: string; driver_name: string; gross_fare_minor: number; commission_minor: number; driver_net_minor: number; payment_method: string; payment_status: string; commission_status: string; currency_code: string; created_at: string }
type AdminPayout = { payout_id: string; driver_id: string; driver_name: string; amount_minor: number; currency_code: string; payout_status: string; payout_reference: string | null; requested_at: string }
type AdminDriver = {
  driver_id: string; user_id: string; display_name: string; account_status: string
  onboarding_status: string; vehicle_id: string | null; vehicle_make: string | null
  vehicle_model: string | null; vehicle_year: number | null; vehicle_color: string | null
  seat_capacity: number | null; vehicle_status: string | null
}
type DriverDocument = { document_id: string; driver_id?: string; user_id?: string; display_name?: string; document_type: string; object_path?: string; status: string; expires_on: string | null; uploaded_at: string; reviewed_at: string | null; review_reason: string | null }
const documentNames: Record<string, string> = { identity_card: 'بطاقة الهوية', driving_license: 'رخصة السياقة', vehicle_registration: 'البطاقة الرمادية', insurance: 'التأمين' }
const requiredDocumentTypes = ['identity_card','driving_license','vehicle_registration','insurance']
const latestDriverDocumentIsApproved = (documents: DriverDocument[], driverId: string | undefined, type: string) => {
  const latest = documents.filter(doc => doc.driver_id === driverId && doc.document_type === type)
    .sort((a, b) => b.uploaded_at.localeCompare(a.uploaded_at))[0]
  return latest?.status === 'approved' && (!latest.expires_on || latest.expires_on >= new Date().toISOString().slice(0, 10))
}
type Tracking = {
  ride_id: string; ride_status: string; pickup_latitude: number; pickup_longitude: number
  destination_latitude: number; destination_longitude: number
  driver_latitude: number | null; driver_longitude: number | null
  route_geometry: { type: 'LineString'; coordinates: [number, number][] } | null
}

const statusNames: Record<string, string> = {
  requested: 'تم إرسال الطلب', offered: 'نبحث عن سائق', accepted: 'قبل السائق الرحلة',
  driver_arriving: 'السائق في الطريق إليك', arrived: 'السائق وصل',
  boarded: 'تم تأكيد الصعود', in_progress: 'الرحلة جارية',
  completed: 'اكتملت الرحلة', cancelled: 'أُلغيت الرحلة',
  expired: 'انتهت صلاحية الطلب', no_driver_found: 'لم نعثر على سائق بعد',
}
const categoryNames: Record<string, string> = { economy: 'اقتصادية', comfort: 'مريحة', family: 'عائلية' }
const activeStatuses = ['accepted', 'driver_arriving', 'arrived', 'boarded', 'in_progress']
const money = (minor: number, currency = 'DZD') =>
  new Intl.NumberFormat('ar-DZ', { style: 'currency', currency, maximumFractionDigits: 2 }).format(minor / 100)
const time = (value: string) => new Date(value).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' })

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [roles, setRoles] = useState<string[]>([])
  const [driverProfile, setDriverProfile] = useState<DriverProfile | null>(null)
  const [passengerRides, setPassengerRides] = useState<Ride[]>([])
  const [driverRides, setDriverRides] = useState<Ride[]>([])
  const [driverEarnings, setDriverEarnings] = useState<DriverEarning[]>([])
  const [driverFinance, setDriverFinance] = useState<DriverFinancialSummary | null>(null)
  const [driverPayoutAmount, setDriverPayoutAmount] = useState('')
  const [adminFinancials, setAdminFinancials] = useState<AdminFinancial[]>([])
  const [adminPayouts, setAdminPayouts] = useState<AdminPayout[]>([])
  const [commissionBps, setCommissionBps] = useState<number | null>(null)
  const [commissionProvisional, setCommissionProvisional] = useState(true)
  const [commissionDraft, setCommissionDraft] = useState('')
  const [paymentReferences, setPaymentReferences] = useState<Record<string, string>>({})
  const [payoutReferences, setPayoutReferences] = useState<Record<string, string>>({})
  const [offers, setOffers] = useState<Offer[]>([])
  const [negotiations, setNegotiations] = useState<FareNegotiation[]>([])
  const [counterAmounts, setCounterAmounts] = useState<Record<string, string>>({})
  const [accounts, setAccounts] = useState<AdminAccount[]>([])
  const [drivers, setDrivers] = useState<AdminDriver[]>([])
  const [driverDocuments, setDriverDocuments] = useState<DriverDocument[]>([])
  const [myDriverDocuments, setMyDriverDocuments] = useState<DriverDocument[]>([])
  const [documentType, setDocumentType] = useState('identity_card')
  const [documentFile, setDocumentFile] = useState<File | null>(null)
  const [documentExpiry, setDocumentExpiry] = useState('')
  const [documentPreviewUrl, setDocumentPreviewUrl] = useState('')
  const [adminRides, setAdminRides] = useState<AdminRide[]>([])
  const [safetyReports, setSafetyReports] = useState<SafetyReport[]>([])
  const [supportTickets, setSupportTickets] = useState<SupportTicket[]>([])
  const [supportMessages, setSupportMessages] = useState<SupportMessage[]>([])
  const [notifications, setNotifications] = useState<UserNotification[]>([])
  const [adminSupportTickets, setAdminSupportTickets] = useState<AdminSupportTicket[]>([])
  const [supportCategory, setSupportCategory] = useState('استفسار عام')
  const [supportMessage, setSupportMessage] = useState('')
  const [adminReplies, setAdminReplies] = useState<Record<string, string>>({})
  const [reportDescription, setReportDescription] = useState('')
  const [ratingScore, setRatingScore] = useState(5)
  const [ratingComment, setRatingComment] = useState('')
  const [ratingStatus, setRatingStatus] = useState<RatingStatus | null>(null)
  const [tracking, setTracking] = useState<Tracking | null>(null)
  const [screen, setScreen] = useState<'passenger' | 'driver' | 'admin'>('passenger')
  const [authMode, setAuthMode] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [pickup, setPickup] = useState<GeoPoint | null>(null)
  const [destination, setDestination] = useState<GeoPoint | null>(null)
  const [pickupLabel, setPickupLabel] = useState('')
  const [destinationLabel, setDestinationLabel] = useState('')
  const [selection, setSelection] = useState<'pickup' | 'destination'>('pickup')
  const [category, setCategory] = useState<'economy' | 'comfort' | 'family'>('economy')
  const [quote, setQuote] = useState<Awaited<ReturnType<typeof createFareQuote>> | null>(null)
  const [driverOnline, setDriverOnline] = useState(false)
  const [vehicleMake, setVehicleMake] = useState('')
  const [vehicleModel, setVehicleModel] = useState('')
  const [vehicleYear, setVehicleYear] = useState(String(new Date().getFullYear() - 5))
  const [vehicleColor, setVehicleColor] = useState('')
  const [seatCapacity, setSeatCapacity] = useState('5')
  const [boardingPin, setBoardingPin] = useState('')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  const passengerRide = useMemo(
    () => passengerRides.find(ride => !['completed', 'cancelled', 'expired'].includes(ride.status)) ?? passengerRides[0] ?? null,
    [passengerRides],
  )
  const driverRide = useMemo(
    () => driverRides.find(ride => activeStatuses.includes(ride.status)) ?? null,
    [driverRides],
  )
  const completedDriverRide = useMemo(
    () => driverRides.find(ride => ride.status === 'completed') ?? null,
    [driverRides],
  )
  const ratingRide = screen === 'driver' ? (!driverRide ? completedDriverRide : null) : passengerRide?.status === 'completed' ? passengerRide : null

  const refreshData = useCallback(async (userId: string) => {
    if (!supabase) return
    const [profileResult, roleResult, ridesResult, driverResult, ticketsResult, messagesResult, notificationsResult] = await Promise.all([
      supabase.from('profiles').select('id,display_name,account_status').eq('id', userId).maybeSingle(),
      supabase.from('user_roles').select('role').eq('user_id', userId),
      supabase.rpc('get_my_passenger_ride_details', { p_limit: 20 }),
      supabase.from('driver_profiles').select('id,onboarding_status,availability_status').eq('user_id', userId).maybeSingle(),
      supabase.from('support_tickets').select('id,category,message,status,created_at,updated_at').eq('user_id', userId).order('updated_at', { ascending: false }).limit(30),
      supabase.from('support_ticket_messages').select('id,ticket_id,body,is_staff,created_at').order('created_at', { ascending: true }).limit(300),
      supabase.from('user_notifications').select('id,notification_type,title,body,created_at,read_at').order('created_at', { ascending: false }).limit(30),
    ])
    if (profileResult.error) throw profileResult.error
    if (roleResult.error) throw roleResult.error
    if (ridesResult.error) throw ridesResult.error
    if (ticketsResult.error) throw ticketsResult.error
    if (messagesResult.error) throw messagesResult.error
    if (notificationsResult.error) throw notificationsResult.error
    setSupportTickets((ticketsResult.data ?? []) as SupportTicket[])
    setSupportMessages((messagesResult.data ?? []) as SupportMessage[])
    setNotifications((notificationsResult.data ?? []) as UserNotification[])
    setProfile(profileResult.data as Profile | null)
    const nextRoles = (roleResult.data ?? []).map(row => row.role as string)
    setRoles(nextRoles)
    setPassengerRides((ridesResult.data ?? []) as Ride[])
    setDriverProfile(driverResult.data as DriverProfile | null)
    setDriverOnline(driverResult.data?.availability_status === 'online')
    const negotiationRows = await getMyFareNegotiations()
    setNegotiations(negotiationRows)

    if (driverResult.data) {
      const [offersResult, driverRidesResult, earningsResult, documentsResult, financeResult] = await Promise.all([
        supabase.rpc('get_my_driver_offers'),
        supabase.rpc('get_my_driver_ride_details', { p_limit: 20 }),
        supabase.rpc('get_my_driver_earnings', { p_limit: 20 }),
        supabase.rpc('get_my_driver_documents'),
        supabase.rpc('get_my_driver_financial_summary'),
      ])
      if (offersResult.error) throw offersResult.error
      if (driverRidesResult.error) throw driverRidesResult.error
      if (earningsResult.error) throw earningsResult.error
      if (documentsResult.error) throw documentsResult.error
      if (financeResult.error) throw financeResult.error
      const financeRow = Array.isArray(financeResult.data) ? financeResult.data[0] : financeResult.data
      setDriverFinance((financeRow as DriverFinancialSummary | null) ?? null)
      setMyDriverDocuments((documentsResult.data ?? []) as DriverDocument[])
      setOffers((offersResult.data ?? []) as Offer[])
      setDriverRides((driverRidesResult.data ?? []) as Ride[])
      setDriverEarnings((earningsResult.data ?? []) as DriverEarning[])
    } else {
      setOffers([])
      setDriverRides([])
      setDriverEarnings([])
      setDriverFinance(null)
      setMyDriverDocuments([])
    }

    if (nextRoles.includes('admin')) {
      const [accountResult, driverQueueResult, rideResult, safetyResult, documentsResult, supportResult, financeResult, payoutResult, commissionResult] = await Promise.all([
        supabase.rpc('admin_list_pending_accounts'),
        supabase.rpc('admin_list_driver_applications'),
        supabase.rpc('admin_list_recent_rides'),
        supabase.rpc('admin_list_safety_reports'),
        supabase.rpc('admin_list_driver_documents'),
        supabase.rpc('admin_list_support_tickets'),
        supabase.rpc('admin_list_financials'),
        supabase.rpc('admin_list_payout_requests'),
        supabase.rpc('admin_get_commission_policy'),
      ])
      if (accountResult.error) throw accountResult.error
      if (driverQueueResult.error) throw driverQueueResult.error
      if (rideResult.error) throw rideResult.error
      if (safetyResult.error) throw safetyResult.error
      if (documentsResult.error) throw documentsResult.error
      if (supportResult.error) throw supportResult.error
      if (financeResult.error) throw financeResult.error
      if (payoutResult.error) throw payoutResult.error
      if (commissionResult.error) throw commissionResult.error
      const policyRow = Array.isArray(commissionResult.data) ? commissionResult.data[0] : commissionResult.data
      setCommissionBps(policyRow?.commission_bps ?? null)
      setCommissionProvisional(policyRow ? Boolean(policyRow.is_provisional) : true)
      if (policyRow?.commission_bps !== undefined) setCommissionDraft(String(Number(policyRow.commission_bps) / 100))
      setAdminFinancials((financeResult.data ?? []) as AdminFinancial[])
      setAdminPayouts((payoutResult.data ?? []) as AdminPayout[])
      setAdminSupportTickets((supportResult.data ?? []) as AdminSupportTicket[])
      setDriverDocuments((documentsResult.data ?? []) as DriverDocument[])
      setAdminRides((rideResult.data ?? []) as AdminRide[])
      setSafetyReports((safetyResult.data ?? []) as SafetyReport[])
      setAccounts((accountResult.data ?? []) as AdminAccount[])
      setDrivers((driverQueueResult.data ?? []) as AdminDriver[])
    } else {
      setAccounts([])
      setDrivers([])
      setDriverDocuments([])
      setAdminRides([])
      setSafetyReports([])
      setAdminSupportTickets([])
      setAdminFinancials([])
      setAdminPayouts([])
      setCommissionBps(null)
      setCommissionProvisional(true)
    }
  }, [])

  useEffect(() => {
    if (!supabase) return
    let alive = true
    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!alive) return
      if (sessionError) setError(sessionError.message)
      setUser(data.session?.user ?? null)
    })
    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
      setScreen('passenger')
      if (!session) {
        void stopDriverBackgroundTracking().catch(() => undefined)
        setProfile(null); setRoles([]); setDriverProfile(null)
        setPassengerRides([]); setDriverRides([]); setOffers([]); setNegotiations([])
        setDriverEarnings([]); setDriverDocuments([]); setMyDriverDocuments([]); setAccounts([])
        setAdminRides([]); setSafetyReports([]); setSupportTickets([]); setSupportMessages([]); setNotifications([]); setAdminSupportTickets([]); setAdminFinancials([]); setAdminPayouts([]); setDriverFinance(null); setDocumentFile(null); setDocumentPreviewUrl('')
      }
    })
    return () => { alive = false; authListener.subscription.unsubscribe() }
  }, [])

  useEffect(() => {
    if (!user) return
    setError('')
    refreshData(user.id).catch(err => setError(err.message ?? 'تعذر تحميل بيانات الحساب.'))
  }, [user, refreshData])

  useEffect(() => {
    if (!supabase || !user) return
    const client = supabase
    const channel = client.channel(`mithaq-user-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rides', filter: `passenger_id=eq.${user.id}` }, () => {
        refreshData(user.id).catch(err => setError(err.message))
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'driver_profiles', filter: `user_id=eq.${user.id}` }, () => {
        refreshData(user.id).catch(err => setError(err.message))
      })
    channel.on('postgres_changes', { event: '*', schema: 'public', table: 'fare_negotiations', filter: `passenger_id=eq.${user.id}` }, () => {
      refreshData(user.id).catch(err => setError(err.message))
    })
    channel.on('postgres_changes', { event: '*', schema: 'public', table: 'user_notifications', filter: `user_id=eq.${user.id}` }, () => {
      refreshData(user.id).catch(err => setError(err.message))
    })
    channel.on('postgres_changes', { event: '*', schema: 'public', table: 'support_tickets', filter: `user_id=eq.${user.id}` }, () => {
      refreshData(user.id).catch(err => setError(err.message))
    })
    if (driverProfile?.id) {
      channel.on('postgres_changes', { event: '*', schema: 'public', table: 'ride_offers', filter: `driver_id=eq.${driverProfile.id}` }, () => {
        refreshData(user.id).catch(err => setError(err.message))
      })
      channel.on('postgres_changes', { event: '*', schema: 'public', table: 'fare_negotiations', filter: `driver_id=eq.${driverProfile.id}` }, () => {
        refreshData(user.id).catch(err => setError(err.message))
      })
    }
    channel.subscribe()
    return () => { void client.removeChannel(channel) }
  }, [user, driverProfile?.id, refreshData])

  // Reconcile the persisted inbox periodically in case a Realtime connection drops.
  useEffect(() => {
    if (!supabase || !user) return
    let alive = true
    const syncNotifications = async () => {
      const { data, error: notificationError } = await supabase!
        .from('user_notifications')
        .select('id,notification_type,title,body,created_at,read_at')
        .order('created_at', { ascending: false })
        .limit(30)
      if (!alive) return
      if (notificationError) { setError(notificationError.message); return }
      setNotifications((data ?? []) as UserNotification[])
    }
    const timer = window.setInterval(() => { void syncNotifications() }, 30000)
    return () => { alive = false; window.clearInterval(timer) }
  }, [user])

  useEffect(() => {
    if (!supabase || !user || !passengerRide || !activeStatuses.includes(passengerRide.status)) {
      setTracking(null)
      return
    }
    const client = supabase
    let mounted = true
    const load = async () => {
      const { data, error: trackingError } = await client.rpc('get_my_ride_tracking', { p_ride_id: passengerRide.id })
      if (!mounted) return
      if (trackingError) { setError(trackingError.message); return }
      const row = Array.isArray(data) ? data[0] : data
      setTracking(row as Tracking | null)
    }
    void load()
    const timer = window.setInterval(() => { void load() }, 8000)
    return () => { mounted = false; window.clearInterval(timer) }
  }, [user, passengerRide?.id, passengerRide?.status])

  useEffect(() => {
    if (!quote) return
    const remaining = new Date(quote.expires_at).getTime() - Date.now()
    if (remaining <= 0) {
      setQuote(null)
      setNotice('انتهت صلاحية عرض السعر. احسبه من جديد قبل تأكيد الرحلة.')
      return
    }
    const timer = window.setTimeout(() => {
      setQuote(null)
      setNotice('انتهت صلاحية عرض السعر. احسبه من جديد قبل تأكيد الرحلة.')
    }, remaining)
    return () => window.clearTimeout(timer)
  }, [quote])

  useEffect(() => {
    if (!supabase || !user || !ratingRide) { setRatingStatus(null); return }
    let mounted = true
    supabase.rpc('get_my_ride_rating_status', { p_ride_id: ratingRide.id }).then(({ data, error: ratingError }) => {
      if (!mounted) return
      if (ratingError) { setError(ratingError.message); return }
      const row = Array.isArray(data) ? data[0] : data
      setRatingStatus((row as RatingStatus | null) ?? null)
    })
    return () => { mounted = false }
  }, [user, ratingRide?.id, screen])

  useEffect(() => {
    if (!driverProfile || !supabase) return
    const active = ['online', 'busy'].includes(driverProfile.availability_status)

    if (isNativeAndroid()) {
      if (!active) {
        void stopDriverBackgroundTracking().catch(err => setError(err instanceof Error ? err.message : 'تعذر إيقاف تتبع الموقع.'))
        return
      }
      let alive = true
      const ensureNativeTracking = async () => {
        const { data, error: sessionError } = await supabase!.auth.getSession()
        if (sessionError) throw sessionError
        if (!data.session?.access_token) throw new Error('انتهت جلسة السائق. سجّل الدخول مجددًا لتشغيل التتبع.')
        await startDriverBackgroundTracking(data.session.access_token, {
          onError: message => { if (alive) setError(message) },
        })
      }
      void ensureNativeTracking().catch(err => {
        if (alive) setError(err instanceof Error ? err.message : 'تعذر تشغيل GPS في الخلفية.')
      })
      const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
        if (!session) {
          void stopDriverBackgroundTracking().catch(err => setError(err instanceof Error ? err.message : 'تعذر إيقاف تتبع الموقع.'))
          return
        }
        void refreshDriverBackgroundTrackingToken(session.access_token).catch(err => {
          setError(err instanceof Error ? err.message : 'تعذر تحديث صلاحية إرسال الموقع.')
        })
      })
      return () => {
        alive = false
        authListener.subscription.unsubscribe()
      }
    }

    if (!active) return
    if (!navigator.geolocation) {
      setError('هذا المتصفح لا يدعم تحديد الموقع؛ لا يمكن إدخالك في المطابقة.')
      return
    }
    const sendLocation = async (position: GeolocationPosition) => {
      if (position.coords.accuracy > 100) return
      try {
        await recordDriverLocation({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracyM: position.coords.accuracy,
          recordedAt: new Date(position.timestamp).toISOString(),
        })
      } catch (err) {
        setError(err instanceof Error ? err.message : 'تعذر إرسال موقع السائق.')
      }
    }
    const watchId = navigator.geolocation.watchPosition(sendLocation, geoError => {
      setError(geoError.code === 1 ? 'يجب السماح بالموقع حتى تظهر لك الطلبات القريبة.' : 'تعذر تحديث موقعك.')
    }, { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 })
    const heartbeat = window.setInterval(() => {
      navigator.geolocation.getCurrentPosition(sendLocation, () => undefined, {
        enableHighAccuracy: true, maximumAge: 0, timeout: 15000,
      })
    }, 20000)
    return () => {
      navigator.geolocation.clearWatch(watchId)
      window.clearInterval(heartbeat)
    }
  }, [driverProfile?.id, driverProfile?.availability_status])

  const run = async (action: () => Promise<void>) => {
    setBusy(true); setError(''); setNotice('')
    try { await action() } catch (err) {
      setError(err instanceof Error ? err.message : 'حدث خطأ غير متوقع.')
    } finally { setBusy(false) }
  }

  const authenticate = () => run(async () => {
    if (!supabase) throw new Error('إعداد الخادم غير مكتمل.')
    if (authMode === 'signup') {
      if (displayName.trim().length < 2) throw new Error('أدخل اسمًا من حرفين على الأقل.')
      const { data, error: authError } = await supabase.auth.signUp({
        email: email.trim(), password,
        options: { data: { display_name: displayName.trim() } },
      })
      if (authError) throw authError
      if (!data.session) setNotice('تم إنشاء الطلب. تحقق من بريدك الإلكتروني لتأكيد الحساب ثم سجّل الدخول.')
      else setNotice('تم إنشاء الحساب. سيبقى قيد المراجعة إلى أن يفعّله المسؤول.')
    } else {
      const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
      if (authError) throw authError
    }
  })

  const signOut = () => run(async () => {
    await stopDriverBackgroundTracking()
    const { error: signOutError } = await supabase!.auth.signOut()
    if (signOutError) throw signOutError
  })

  const getQuote = () => run(async () => {
    if (!pickup || !destination) throw new Error('حدد نقطة الانطلاق والوجهة على الخريطة أولاً.')
    if (!pickupLabel.trim() || !destinationLabel.trim()) throw new Error('اكتب وصفًا واضحًا لنقطتي الانطلاق والوجهة.')
    const result = await createFareQuote({
      pickup_label: pickupLabel.trim(), destination_label: destinationLabel.trim(),
      pickup, destination, category,
    })
    setQuote(result)
    setNotice(`تم حساب السعر لمسافة ${(result.route_distance_m / 1000).toFixed(1)} كم. العرض صالح لثلاث دقائق.`)
  })

  const bookRide = () => run(async () => {
    if (!quote) throw new Error('احسب السعر أولاً.')
    if (new Date(quote.expires_at).getTime() <= Date.now()) {
      setQuote(null)
      throw new Error('انتهت صلاحية عرض السعر. احسبه من جديد.')
    }
    const result = await requestRide(quote.quote_id)
    setQuote(null)
    setNotice(`تم إنشاء الطلب. رمز الصعود الخاص بك: ${result.boarding_pin}`)
    await refreshData(user!.id)
  })

  const cancelRide = (rideId: string, reason: 'passenger_changed_plans' | 'driver_unavailable') => run(async () => {
    const { error: rpcError } = await supabase!.rpc('cancel_ride', { p_ride_id: rideId, p_reason: reason })
    if (rpcError) throw rpcError
    await refreshData(user!.id)
    setNotice('تم إلغاء الرحلة وتسجيل سبب الإلغاء.')
  })

  const updateDriverRide = (ride: Ride) => run(async () => {
    const next = ride.status === 'accepted' ? 'driver_arriving'
      : ride.status === 'driver_arriving' ? 'arrived'
      : ride.status === 'arrived' ? 'boarded'
      : ride.status === 'boarded' ? 'in_progress'
      : ride.status === 'in_progress' ? 'completed' : null
    if (!next) return
    if (next === 'boarded' && !/^\d{6}$/.test(boardingPin)) throw new Error('أدخل رمز الصعود المكوّن من ستة أرقام.')
    const { error: rpcError } = await supabase!.rpc('advance_ride', {
      p_ride_id: ride.id, p_next_status: next,
      p_boarding_pin: next === 'boarded' ? boardingPin : null,
    })
    if (rpcError) throw rpcError
    setBoardingPin('')
    await refreshData(user!.id)
    setNotice(`تم تحديث حالة الرحلة: ${statusNames[next]}.`)
  })

  const toggleOnline = () => run(async () => {
    if (!driverOnline) {
      if (isNativeAndroid() && !window.confirm('عند تفعيل التوفر، يرسل MITHAQ موقعك لتحديد الرحلات القريبة ويظهر إشعار تتبع دائم. أثناء الرحلة لا يرى موقعك إلا الراكب المرتبط بها. يمكنك إيقاف التتبع بإيقاف التوفر. هل توافق؟')) return
      if (!navigator.geolocation) throw new Error('تحديد الموقع غير مدعوم في هذا المتصفح.')
      const position = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true, maximumAge: 0, timeout: 15000,
        })
      })
      if (position.coords.accuracy > 100) {
        throw new Error('دقة الموقع ضعيفة. انتقل إلى مكان مفتوح وحاول مجددًا.')
      }
      await setDriverAvailability(true)
      try {
        await recordDriverLocation({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracyM: position.coords.accuracy,
          recordedAt: new Date(position.timestamp).toISOString(),
        })
        if (isNativeAndroid()) {
          const { data, error: sessionError } = await supabase!.auth.getSession()
          if (sessionError) throw sessionError
          if (!data.session?.access_token) throw new Error('انتهت جلسة الدخول. أعد تسجيل الدخول.')
          await startDriverBackgroundTracking(data.session.access_token, {
            onError: message => setError(message),
          })
        }
      } catch (locationError) {
        await stopDriverBackgroundTracking().catch(() => undefined)
        await setDriverAvailability(false)
        throw locationError
      }
      setDriverOnline(true)
      setDriverProfile(current => current ? { ...current, availability_status: 'online' } : current)
      await refreshData(user!.id)
      setNotice(isNativeAndroid()
        ? 'أصبحت متاحًا. يعمل تتبع GPS في الخلفية مع إشعار ظاهر ويمكنه الاستمرار عند قفل الشاشة.'
        : 'أصبحت متاحًا. سيُحدّث المتصفح موقعك أثناء بقاء التطبيق مفتوحًا.')
    } else {
      let stopError: unknown = null
      try { await stopDriverBackgroundTracking() } catch (err) { stopError = err }
      await setDriverAvailability(false)
      await refreshData(user!.id)
      if (stopError) throw stopError
      setNotice('أصبحت غير متاح، وتم إيقاف تتبع الموقع.')
    }
  })

  const applyDriver = () => run(async () => {
    const { error: applyError } = await supabase!.rpc('apply_as_driver')
    if (applyError) throw applyError
    await refreshData(user!.id)
    setNotice('تم إنشاء طلب الانضمام كسائق. أضف بيانات المركبة لإرسال الملف للمراجعة.')
  })

  const submitVehicle = () => run(async () => {
    const { error: vehicleError } = await supabase!.rpc('submit_driver_vehicle', {
      p_make: vehicleMake, p_model: vehicleModel,
      p_model_year: vehicleYear ? Number(vehicleYear) : null,
      p_color: vehicleColor || null, p_seat_capacity: Number(seatCapacity),
    })
    if (vehicleError) throw vehicleError
    await refreshData(user!.id)
    setNotice('تم إرسال بيانات المركبة للمراجعة. لن تتمكن من استقبال رحلات حتى اعتماد الحساب والمركبة.')
  })

  const submitDriverDocument = () => run(async () => {
    if (!supabase || !user || !driverProfile) throw new Error('أنشئ طلب سائق أولاً.')
    if (!documentFile) throw new Error('اختر ملف الوثيقة أولاً.')
    if (documentFile.size > 10 * 1024 * 1024) throw new Error('الحد الأقصى لحجم الملف 10 ميغابايت.')
    if (!['application/pdf','image/jpeg','image/png'].includes(documentFile.type)) throw new Error('الصيغ المقبولة PDF أو JPG أو PNG.')
    if (documentType === 'insurance' && !documentExpiry) throw new Error('أدخل تاريخ انتهاء التأمين.')
    if (documentExpiry && documentExpiry < new Date().toISOString().slice(0,10)) throw new Error('تاريخ الانتهاء يجب أن يكون في المستقبل.')
    const extension = documentFile.type === 'application/pdf' ? 'pdf' : documentFile.type === 'image/png' ? 'png' : 'jpg'
    const objectPath = user.id + '/' + driverProfile.id + '/' + documentType + '/' + crypto.randomUUID() + '.' + extension
    const { error: uploadError } = await supabase.storage.from('driver-documents').upload(objectPath, documentFile, {
      contentType: documentFile.type, cacheControl: '60', upsert: false,
    })
    if (uploadError) throw uploadError
    const { error: registerError } = await supabase.rpc('register_my_driver_document', {
      p_document_type: documentType, p_object_path: objectPath,
      p_expires_on: documentExpiry || null,
    })
    if (registerError) {
      await supabase.storage.from('driver-documents').remove([objectPath])
      throw registerError
    }
    setDocumentFile(null)
    setDocumentExpiry('')
    await refreshData(user.id)
    setNotice('تم رفع الوثيقة بأمان وإرسالها للمراجعة. لا يمكن تفعيل السائق قبل اعتماد الوثائق الأربع.')
  })

  const reviewDriverDocument = (documentId: string, decision: 'approved' | 'rejected') => run(async () => {
    const { error: reviewError } = await supabase!.rpc('admin_review_driver_document', {
      p_document_id: documentId, p_decision: decision,
      p_reason: decision === 'approved' ? 'تمت مراجعة الوثيقة ومطابقة بياناتها.' : 'الوثيقة غير واضحة أو غير مطابقة؛ يرجى إعادة رفعها.',
    })
    if (reviewError) throw reviewError
    await refreshData(user!.id)
    setNotice(decision === 'approved' ? 'تم اعتماد الوثيقة.' : 'تم رفض الوثيقة.')
  })

  const previewDriverDocument = (objectPath: string) => run(async () => {
    const { data, error: signedUrlError } = await supabase!.storage.from('driver-documents').createSignedUrl(objectPath, 60)
    if (signedUrlError) throw signedUrlError
    setDocumentPreviewUrl(data.signedUrl)
    setNotice('رابط الوثيقة صالح لمدة 60 ثانية. افتحه من زر المعاينة.')
  })

  const acceptOffer = (offerId: string) => run(async () => {
    const { error: acceptError } = await supabase!.rpc('accept_ride_offer', { p_offer_id: offerId })
    if (acceptError) throw acceptError
    await refreshData(user!.id)
    setNotice('قبلت الرحلة. اتبع مراحل الرحلة ورمز الصعود.')
  })

  const declineOffer = (offerId: string) => run(async () => {
    const { error: declineError } = await supabase!.rpc('decline_ride_offer', { p_offer_id: offerId })
    if (declineError) throw declineError
    await refreshData(user!.id)
  })

  const beginFareNegotiation = (offerId: string) => run(async () => {
    const raw = counterAmounts[offerId] ?? ''
    const amountDzd = Number(raw)
    if (!Number.isFinite(amountDzd) || amountDzd <= 0 || !Number.isSafeInteger(amountDzd * 100)) {
      throw new Error('أدخل عرضاً صحيحاً بالدينار الجزائري.')
    }
    await startFareNegotiation(offerId, amountDzd * 100)
    await refreshData(user!.id)
    setNotice('أرسلت عرضك المضاد. ينتظر التفاوض رد الراكب.')
  })

  const answerFareNegotiation = (negotiation: FareNegotiation, action: 'counter' | 'accept' | 'reject') => run(async () => {
    const raw = counterAmounts[negotiation.negotiation_id] ?? ''
    const amountDzd = Number(raw)
    const amountMinor = action === 'counter' ? amountDzd * 100 : undefined
    if (action === 'counter' && (!Number.isFinite(amountDzd) || amountDzd <= 0 || !Number.isSafeInteger(amountMinor))) {
      throw new Error('أدخل عرضاً صحيحاً بالدينار الجزائري.')
    }
    const result = await respondFareNegotiation(negotiation.negotiation_id, action, amountMinor)
    await refreshData(user!.id)
    setNotice(result === 'accepted' ? 'تم الاتفاق على السعر وتأكيد إسناد الرحلة.' : result === 'rejected' ? 'تم رفض التفاوض.' : result === 'expired' ? 'انتهت صلاحية التفاوض.' : 'تم إرسال ردك على السعر.')
  })

  const submitRating = () => run(async () => {
    if (!ratingRide) throw new Error('لا توجد رحلة مكتملة لتقييمها.')
    const { error: ratingError } = await supabase!.rpc('submit_ride_rating', {
      p_ride_id: ratingRide.id, p_score: ratingScore, p_comment: ratingComment.trim(),
    })
    if (ratingError) throw ratingError
    setRatingComment('')
    await refreshData(user!.id)
    const { data } = await supabase!.rpc('get_my_ride_rating_status', { p_ride_id: ratingRide.id })
    const row = Array.isArray(data) ? data[0] : data
    setRatingStatus((row as RatingStatus | null) ?? null)
    setNotice('شكرًا لك. تم حفظ تقييم الرحلة.')
  })

  const submitSafetyReport = (rideId: string | null) => run(async () => {
    if (reportDescription.trim().length < 5) throw new Error('اكتب تفاصيل البلاغ (5 أحرف على الأقل).')
    const { error: reportError } = await supabase!.rpc('submit_safety_report', {
      p_ride_id: rideId, p_category: 'trip_issue', p_severity: 'normal',
      p_description: reportDescription.trim(),
    })
    if (reportError) throw reportError
    setReportDescription('')
    setNotice('تم إرسال البلاغ إلى سجل المراجعة في بيئة الاختبار.')
  })

  const createSupportTicket = () => run(async () => {
    if (supportMessage.trim().length < 5) throw new Error('اكتب تفاصيل طلب الدعم (5 أحرف على الأقل).')
    const relatedRideId = screen === 'driver' ? driverRide?.id ?? null : passengerRide?.id ?? null
    const { data, error: ticketError } = await supabase!.rpc('create_support_ticket', {
      p_category: supportCategory, p_message: supportMessage.trim(), p_ride_id: relatedRideId,
    })
    if (ticketError) throw ticketError
    setSupportMessage('')
    await refreshData(user!.id)
    setNotice('تم فتح تذكرة دعم رقم ' + String(data).slice(0, 8) + '، ويمكنك متابعة الردود من سجل التذاكر.')
  })

  const markNotificationRead = (notificationId: string) => run(async () => {
    const { error: readError } = await supabase!.from('user_notifications').update({ read_at: new Date().toISOString() }).eq('id', notificationId)
    if (readError) throw readError
    setNotifications(items => items.map(item => item.id === notificationId ? { ...item, read_at: new Date().toISOString() } : item))
  })

  const replySupportTicket = (ticketId: string, status: 'assigned' | 'resolved' | 'closed') => run(async () => {
    const body = (adminReplies[ticketId] ?? '').trim()
    if (body.length < 2) throw new Error('اكتب رد الإدارة قبل إرسال التحديث.')
    const { error: replyError } = await supabase!.rpc('admin_reply_support_ticket', { p_ticket_id: ticketId, p_body: body, p_status: status })
    if (replyError) throw replyError
    setAdminReplies(items => ({ ...items, [ticketId]: '' }))
    await refreshData(user!.id)
    setNotice('تم إرسال رد الإدارة وتحديث حالة التذكرة.')
  })

  const updateSafetyReport = (reportId: string, status: 'investigating' | 'resolved' | 'closed') => run(async () => {
    const { error: reportError } = await supabase!.rpc('admin_update_safety_report', {
      p_report_id: reportId, p_status: status,
      p_reason: status === 'investigating' ? 'بدأت مراجعة البلاغ.' : status === 'resolved' ? 'تمت مراجعة البلاغ وحلّه في بيئة الاختبار.' : 'أُغلق البلاغ بعد المراجعة.',
    })
    if (reportError) throw reportError
    await refreshData(user!.id)
  })


  const requestDriverPayout = () => run(async () => {
    const amountDzd = Number(driverPayoutAmount)
    const amountMinor = Math.round(amountDzd * 100)
    if (!Number.isFinite(amountDzd) || amountDzd <= 0 || !Number.isSafeInteger(amountMinor)) {
      throw new Error('أدخل مبلغ تسوية صحيحاً بالدينار الجزائري.')
    }
    const { error: payoutError } = await supabase!.rpc('request_driver_payout', { p_amount_minor: amountMinor })
    if (payoutError) throw payoutError
    setDriverPayoutAmount('')
    await refreshData(user!.id)
    setNotice('تم إرسال طلب التسوية إلى الإدارة للمراجعة.')
  })

  const updatePlatformCommission = () => run(async () => {
    if (!commissionDraft.trim()) throw new Error('أدخل نسبة العمولة التي وافقت عليها الإدارة أولاً.')
    const percent = Number(commissionDraft)
    const basisPoints = Math.round(percent * 100)
    if (!Number.isFinite(percent) || percent < 0 || percent > 30 || !Number.isSafeInteger(basisPoints)) {
      throw new Error('العمولة يجب أن تكون بين 0% و30%.')
    }
    const { error: commissionError } = await supabase!.rpc('admin_set_platform_commission', { p_commission_bps: basisPoints })
    if (commissionError) throw commissionError
    await refreshData(user!.id)
    setNotice('تم حفظ سياسة العمولة الجديدة. ستُطبق على الرحلات المكتملة لاحقاً فقط.')
  })

  const recordRidePayment = (rideId: string, method: 'cash_to_driver' | 'manual_transfer_to_platform') => run(async () => {
    const reference = (paymentReferences[rideId] ?? '').trim()
    if (reference.length < 3) throw new Error('أدخل مرجع التحصيل أو رقم الإيصال.')
    const { error: paymentError } = await supabase!.rpc('admin_record_ride_payment', {
      p_ride_id: rideId, p_payment_method: method, p_reference: reference,
    })
    if (paymentError) throw paymentError
    setPaymentReferences(items => ({ ...items, [rideId]: '' }))
    await refreshData(user!.id)
    setNotice('تم تسجيل التحصيل وإنشاء القيد المالي.')
  })


  const recordCommissionPayment = (rideId: string) => run(async () => {
    const reference = (paymentReferences[rideId] ?? '').trim()
    if (reference.length < 3) throw new Error('أدخل مرجع تسديد العمولة.')
    const { error: commissionError } = await supabase!.rpc('admin_record_driver_commission_payment', {
      p_ride_id: rideId, p_reference: reference,
    })
    if (commissionError) throw commissionError
    setPaymentReferences(items => ({ ...items, [rideId]: '' }))
    await refreshData(user!.id)
    setNotice('تم تسجيل تسديد عمولة المنصة.')
  })

  const processDriverPayout = (payoutId: string, decision: 'approve' | 'pay' | 'reject') => run(async () => {
    const reference = (payoutReferences[payoutId] ?? '').trim()
    if (decision === 'pay' && reference.length < 3) throw new Error('أدخل مرجع التحويل قبل تأكيد الدفع.')
    const { error: payoutError } = await supabase!.rpc('admin_process_driver_payout', {
      p_payout_id: payoutId, p_decision: decision,
      p_reference: decision === 'pay' ? reference : null,
      p_note: decision === 'reject' ? 'تم رفض الطلب بعد المراجعة.' : decision === 'approve' ? 'تمت الموافقة على الطلب.' : 'تم تأكيد التحويل اليدوي.',
    })
    if (payoutError) throw payoutError
    await refreshData(user!.id)
    setNotice(decision === 'pay' ? 'تم تسجيل تسوية مستحقات السائق.' : decision === 'approve' ? 'تمت الموافقة على طلب التسوية.' : 'تم رفض طلب التسوية.')
  })

  const reviewAccount = (userId: string) => run(async () => {
    const { error: reviewError } = await supabase!.rpc('admin_set_account_status', {
      p_user_id: userId, p_status: 'active', p_reason: 'تم التحقق اليدوي لحساب بيئة الاختبار.',
    })
    if (reviewError) throw reviewError
    await refreshData(user!.id)
    setNotice('تم تفعيل الحساب.')
  })

  const reviewVehicle = (vehicleId: string, decision: 'approved' | 'rejected') => run(async () => {
    const { error: reviewError } = await supabase!.rpc('admin_review_vehicle', {
      p_vehicle_id: vehicleId, p_decision: decision,
      p_reason: decision === 'approved' ? 'تم التحقق من بيانات المركبة في بيئة الاختبار.' : 'لم تستوفِ بيانات المركبة شروط المراجعة.',
    })
    if (reviewError) throw reviewError
    await refreshData(user!.id)
  })

  const reviewDriver = (driverId: string, decision: 'approved' | 'rejected') => run(async () => {
    const { error: reviewError } = await supabase!.rpc('admin_review_driver', {
      p_driver_id: driverId, p_decision: decision,
      p_reason: decision === 'approved' ? 'اكتملت مراجعة ملف السائق والمركبة لبيئة الاختبار.' : 'لم يستوفِ ملف السائق شروط المراجعة.',
    })
    if (reviewError) throw reviewError
    await refreshData(user!.id)
  })

  if (!isSupabaseConfigured) {
    return <div className="auth-shell"><section className="auth-card"><Brand/><h1>الخادم لم يُربط بعد</h1><p>الواجهة جاهزة للاتصال، لكن يلزم إنشاء مشروع Supabase وإضافة عنوانه ومفتاحه العام في إعدادات البناء. لا تدخل أي كلمة مرور قبل إتمام الربط.</p><a href="https://supabase.com/dashboard" target="_blank" rel="noreferrer">فتح لوحة Supabase</a></section></div>
  }

  if (!user) {
    return <div className="auth-shell"><section className="auth-card">
      <Brand/><span className="section-kicker">حساب MITHAQ</span>
      <h1>{authMode === 'signin' ? 'مرحبًا بعودتك' : 'أنشئ حسابًا جديدًا'}</h1>
      <p>حساب الراكب والسائق مستقل. الحسابات الجديدة تحتاج تفعيل المسؤول قبل طلب الرحلات أو استقبالها.</p>
      {authMode === 'signup' && <label className="auth-field">الاسم الكامل<input value={displayName} onChange={e => setDisplayName(e.target.value)} autoComplete="name" /></label>}
      <label className="auth-field">البريد الإلكتروني<input type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" /></label>
      <label className="auth-field">كلمة المرور<input type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete={authMode === 'signin' ? 'current-password' : 'new-password'} minLength={8} /></label>
      {error && <div className="alert error">{error}</div>}
      {notice && <div className="alert success">{notice}</div>}
      <button className="primary-btn" disabled={busy || !email.trim() || password.length < 8} onClick={authenticate}>{busy ? 'جارٍ التنفيذ…' : authMode === 'signin' ? 'تسجيل الدخول' : 'إنشاء الحساب'}</button>
      <button className="link-button" onClick={() => {setAuthMode(authMode === 'signin' ? 'signup' : 'signin');setError('');setNotice('')}}>{authMode === 'signin' ? 'ليس لديك حساب؟ أنشئ حسابًا' : 'لديك حساب بالفعل؟ سجّل الدخول'}</button>
    </section></div>
  }

  return <div className="app-shell">
    <header className="topbar">
      <Brand/>
      <div className="top-actions">
        <span className="secure-label"><ShieldCheck size={15}/> بيئة اختبار MITHAQ</span>
        <span className="user-chip"><UserRound size={15}/>{profile?.display_name || user.email}</span>
        <button className="icon-btn" title="تسجيل الخروج" onClick={signOut}><LogOut size={18}/></button>
      </div>
    </header>
    <div className="layout">
      <aside className="sidebar">
        <div className="side-caption">مساحة العمل</div>
        <button className={screen === 'passenger' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('passenger')}><MapPin size={18}/> الراكب</button>
        <button className={screen === 'driver' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('driver')}><CarFront size={18}/> السائق</button>
        {roles.includes('admin') && <button className={screen === 'admin' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('admin')}><ShieldCheck size={18}/> الإدارة</button>}
        <div className="side-bottom"><div className="help-card"><CircleHelp size={19}/><b>اختبار مغلق</b><p>لا توجد رحلات تجارية أو دعم طوارئ في هذه البيئة.</p></div><small>نسخة اختبار متصلة بالخادم</small></div>
      </aside>
      <main className="main">
        <div className="welcome-row"><div><div className="eyebrow">MITHAQ · بيئة اختبار مغلقة</div><h1>{screen === 'passenger' ? 'احجز رحلتك' : screen === 'driver' ? 'مساحة السائق' : 'مركز الإدارة'}</h1><p>{profile?.account_status === 'active' ? 'حسابك مفعّل.' : 'حسابك قيد المراجعة؛ بعض الوظائف غير متاحة بعد.'}</p></div><button className="refresh-button" onClick={() => refreshData(user.id)}><RefreshCw size={15}/> تحديث</button></div>
        {error && <div className="alert error">{error}<button onClick={() => setError('')}>إغلاق</button></div>}
        {notice && <div className="alert success">{notice}<button onClick={() => setNotice('')}>إغلاق</button></div>}

        <section className="panel notification-panel">
          <div className="panel-heading"><div><span className="section-kicker">مركز التنبيهات</span><h2>إشعاراتك ({notifications.filter(item => !item.read_at).length} غير مقروءة)</h2></div></div>
          {!notifications.length && <p className="muted">ستظهر هنا تحديثات الرحلات وعروض السائق وردود الدعم.</p>}
          {notifications.slice(0, 8).map(item => <div className="admin-row" key={item.id}><div><b>{item.title}</b><small>{item.body} · {time(item.created_at)}</small></div>{!item.read_at && <button className="text-button" disabled={busy} onClick={() => markNotificationRead(item.id)}>تمت القراءة</button>}</div>)}
        </section>

        <section className="panel support-center">
          <span className="section-kicker">الدعم والشكاوى</span><h2>كيف يمكننا مساعدتك؟</h2>
          <label className="field-label">نوع الطلب<select className="wide-input" value={supportCategory} onChange={e => setSupportCategory(e.target.value)}><option>استفسار عام</option><option>مشكلة في الرحلة</option><option>مشكلة في السائق أو الراكب</option><option>الدفع أو الأجرة</option><option>السلامة</option><option>اقتراح أو شكوى</option></select></label>
          <textarea value={supportMessage} onChange={e => setSupportMessage(e.target.value)} placeholder="اشرح طلبك أو شكواك بالتفصيل…" rows={3} maxLength={4000}/>
          <button className="secondary-btn" disabled={busy || supportMessage.trim().length < 5} onClick={createSupportTicket}>إرسال إلى الدعم</button>
          <small>تُحفظ التذكرة ويمكنك متابعة ردود الفريق من سجلّك. إذا كان البلاغ متعلقاً برحلة نشطة فسيُربط بها تلقائياً.</small>
          {supportTickets.length > 0 && <><h3>تذاكرك ({supportTickets.length})</h3>{supportTickets.map(ticket => <div className="admin-row" key={ticket.id}><div><b>{ticket.category} · {ticket.status === 'open' ? 'مفتوحة' : ticket.status === 'assigned' ? 'قيد المعالجة' : ticket.status === 'resolved' ? 'تم الحل' : 'مغلقة'}</b><small>{ticket.message} · آخر تحديث {time(ticket.updated_at)}</small>{supportMessages.filter(message => message.ticket_id === ticket.id).slice(-5).map(message => <small key={message.id}>{message.is_staff ? 'الدعم: ' : 'أنت: '}{message.body}</small>)}</div></div>)}</>}
        </section>

        {screen === 'passenger' && <div className="content-grid">
          <section className="panel booking-panel">
            <div className="panel-heading"><div><span className="section-kicker">طلب رحلة</span><h2>أين تريد الذهاب؟</h2></div><span className="heading-icon"><Navigation size={20}/></span></div>
            {profile?.account_status !== 'active' && <div className="alert warning">حسابك غير مفعّل بعد. يمكنك إعداد الرحلة لكن لن يسمح الخادم بإنشائها.</div>}
            <div className="selection-switch">
              <button className={selection === 'pickup' ? 'selected' : ''} onClick={() => setSelection('pickup')}>تحديد الانطلاق</button>
              <button className={selection === 'destination' ? 'selected' : ''} onClick={() => setSelection('destination')}>تحديد الوجهة</button>
            </div>
            <label className="field-label">وصف نقطة الانطلاق<input className="wide-input" value={pickupLabel} onChange={e => setPickupLabel(e.target.value)} placeholder="مثلاً: أمام الجامعة" /></label>
            <label className="field-label">وصف الوجهة<input className="wide-input" value={destinationLabel} onChange={e => setDestinationLabel(e.target.value)} placeholder="مثلاً: وسط المدينة" /></label>
            <div className="field-label">فئة المركبة</div>
            <div className="categories">{(['economy','comfort','family'] as const).map(c => <button key={c} className={category === c ? 'category selected' : 'category'} onClick={() => {setCategory(c);setQuote(null)}}><CarFront size={20}/><b>{categoryNames[c]}</b></button>)}</div>
            <div className="fare-box"><div><small>التسعير الموثوق</small><strong>{quote ? money(quote.amount_minor, quote.currency_code) : 'احسب السعر أولاً'}</strong><span>{quote ? `${(quote.route_distance_m / 1000).toFixed(1)} كم · نحو ${Math.ceil(quote.route_duration_s / 60)} دقيقة · ينتهي ${time(quote.expires_at)}` : 'يُحسب من مسار الطريق وسياسة المنطقة الفعالة'}</span></div><div className="fare-icon"><Wallet size={22}/></div></div>
            <button className="primary-btn" disabled={busy || profile?.account_status !== 'active' || !pickup || !destination} onClick={getQuote}>حساب السعر من الطريق</button>
            {quote && <button className="primary-btn confirm-btn" disabled={busy} onClick={bookRide}>تأكيد طلب الرحلة</button>}
            <p className="microcopy"><ShieldCheck size={14}/> لا توجد مدفوعات إلكترونية في هذه المرحلة.</p>
            {passengerRide && !['completed','cancelled','expired'].includes(passengerRide.status) && <div className="safety-report-form">
              <b>الإبلاغ عن مشكلة في الرحلة</b>
              <textarea value={reportDescription} onChange={e => setReportDescription(e.target.value)} placeholder="اكتب ما حدث باختصار…" rows={2}/>
              <button className="secondary-btn" disabled={busy || reportDescription.trim().length < 5} onClick={() => submitSafetyReport(passengerRide.id)}>إرسال بلاغ</button>
              <small>هذه قناة بلاغات داخلية للاختبار وليست خدمة طوارئ.</small>
            </div>}
            {ratingRide && screen === 'passenger' && <RatingPanel ratingStatus={ratingStatus} ratingScore={ratingScore} setRatingScore={setRatingScore} ratingComment={ratingComment} setRatingComment={setRatingComment} busy={busy} submit={submitRating}/>}
            {negotiations.filter(item => item.passenger_id === user?.id && item.status === 'open').map(item => <section className="panel" key={item.negotiation_id}><span className="section-kicker">تفاوض على السعر</span><h3>{item.pickup_label} ← {item.destination_label}</h3><p>عرض السائق: <b>{money(item.current_amount_minor, item.currency_code)}</b></p><small>النطاق المسموح: {money(item.minimum_amount_minor, item.currency_code)} – {money(item.maximum_amount_minor, item.currency_code)} · الجولة {item.round_number}/{item.max_rounds}</small><small>ينتهي {time(item.expires_at)}</small>{item.last_actor === 'driver' ? <><label className="field-label">عرضك المضاد بالدينار<input className="wide-input" type="number" min="1" value={counterAmounts[item.negotiation_id] ?? ''} onChange={e => setCounterAmounts(v => ({...v,[item.negotiation_id]:e.target.value}))}/></label><div className="offer-buttons"><button className="primary-btn" disabled={busy} onClick={() => answerFareNegotiation(item,'accept')}>قبول السعر</button><button className="secondary-btn" disabled={busy || item.round_number >= item.max_rounds} onClick={() => answerFareNegotiation(item,'counter')}>اقتراح سعر</button><button className="secondary-btn" disabled={busy} onClick={() => answerFareNegotiation(item,'reject')}>رفض</button></div></> : <p className="muted">أرسلت آخر عرض؛ ننتظر رد السائق.</p>}</section>)}
           {passengerRide && <div className="ride-summary"><span className="section-kicker">آخر رحلة</span><h3>{statusNames[passengerRide.status] ?? passengerRide.status}</h3><p>{passengerRide.pickup_label} ← {passengerRide.destination_label}</p>{passengerRide.driver_name && <p>السائق: {passengerRide.driver_name} · المركبة: {passengerRide.vehicle_make ?? ''} {passengerRide.vehicle_model ?? ''} {passengerRide.vehicle_color ?? ''}</p>}<b>{money(passengerRide.quoted_amount_minor, passengerRide.currency_code)}</b>{!['completed','cancelled','expired','boarded','in_progress'].includes(passengerRide.status) && <button className="text-button" onClick={() => cancelRide(passengerRide.id, 'passenger_changed_plans')}>إلغاء الرحلة</button>}</div>}
          </section>
          <section className="panel map-panel">
            <div className="map-top"><span className="map-tag"><MapPin size={14}/> خريطة فعلية</span><span className="map-muted">اختر النقاط مباشرة</span></div>
            <MapPicker pickup={pickup ?? (tracking ? {latitude: tracking.pickup_latitude, longitude: tracking.pickup_longitude} : null)} destination={destination ?? (tracking ? {latitude: tracking.destination_latitude, longitude: tracking.destination_longitude} : null)} driverLocation={tracking?.driver_latitude != null && tracking?.driver_longitude != null ? {latitude: tracking.driver_latitude, longitude: tracking.driver_longitude} : null} routeCoordinates={quote?.route_geometry.coordinates ?? tracking?.route_geometry?.coordinates ?? null} selection={selection} onSelect={point => {
              if (selection === 'pickup') {setPickup(point);setPickupLabel(label => label || 'نقطة الانطلاق المحددة')}
              else {setDestination(point);setDestinationLabel(label => label || 'الوجهة المحددة')}
              setQuote(null)
            }} onLocate={point => {setPickup(point);setPickupLabel('موقعي الحالي');setSelection('destination');setQuote(null)}}/>
            <p className="microcopy">بيانات الخريطة © OpenStreetMap · حساب المسار OSRM.</p>
            {tracking && <p className="microcopy">موقع السائق يُعرض فقط أثناء الرحلة النشطة ولأطراف الرحلة.</p>}
          </section>
        </div>}

        {screen === 'driver' && <div className="driver-grid">
          <section className="panel driver-status"><span className="section-kicker">ملف السائق</span><h2>{driverProfile ? driverProfile.onboarding_status === 'approved' ? 'مقبول في بيئة الاختبار' : 'ملف قيد المراجعة' : 'انضم كسائق'}</h2>
            {!driverProfile && <><p>ابدأ بإرسال طلب انضمام. يجب أن يكون حسابك مفعّلاً.</p><button className="primary-btn" disabled={busy || profile?.account_status !== 'active'} onClick={applyDriver}>طلب الانضمام كسائق</button></>}
            {driverProfile && driverProfile.onboarding_status !== 'approved' && <div className="alert warning">لا يمكنك استقبال الرحلات حتى اعتماد ملف السائق والمركبة من الإدارة.</div>}
            {driverProfile?.onboarding_status === 'approved' && <>
              {driverProfile.availability_status === 'busy'
                ? <div className="alert success">أنت في رحلة نشطة. يستمر تحديث GPS لهذه الرحلة فقط، ولن تستقبل عروضًا جديدة.</div>
                : <><p>حالة التوفر: {driverOnline ? 'متصل' : 'غير متصل'}</p><button className={driverOnline ? 'secondary-btn' : 'primary-btn'} disabled={busy} onClick={toggleOnline}>{driverOnline ? 'إيقاف التوفر' : 'تفعيل التوفر'}</button></>}
              <p className="microcopy">يلزم السماح بالموقع. أثناء الرحلة النشطة يستمر إرسال الموقع للراكب المعني فقط.</p>
            </>}
          </section>
          {driverProfile && <section className="panel">
            <span className="section-kicker">التحقق من الهوية والمركبة</span><h2>وثائق السائق</h2>
            <p className="muted">ارفع الوثائق الأصلية بصيغة PDF أو JPG أو PNG. الملفات خاصة ولا يطلع عليها إلا حسابك وفريق المراجعة المخوّل. الحد الأقصى 10 ميغابايت للملف.</p>
            <div className="admin-row"><b>الوثائق المطلوبة</b><small>{requiredDocumentTypes.filter(type => {
              const latest = myDriverDocuments.filter(doc => doc.document_type === type).sort((a,b) => b.uploaded_at.localeCompare(a.uploaded_at))[0]
              return latest?.status === 'approved' && (!latest.expires_on || latest.expires_on >= new Date().toISOString().slice(0,10))
            }).length} / 4 معتمدة</small></div>
            {requiredDocumentTypes.map(type => {
              const latest = myDriverDocuments.filter(doc => doc.document_type === type).sort((a,b) => b.uploaded_at.localeCompare(a.uploaded_at))[0]
              return <div className="admin-row" key={type}><div><b>{documentNames[type]}</b><small>{latest ? 'الحالة: ' + (latest.status === 'approved' ? 'معتمدة' : latest.status === 'rejected' ? 'مرفوضة' : 'قيد المراجعة') + ' · ' + (latest.expires_on ? 'صالحة حتى ' + latest.expires_on : 'دون تاريخ انتهاء مسجل') : 'لم تُرفع بعد'}{latest?.review_reason ? ' · ' + latest.review_reason : ''}</small></div></div>
            })}
            <label className="auth-field">نوع الوثيقة
              <select value={documentType} onChange={e => setDocumentType(e.target.value)}>
                {requiredDocumentTypes.map(type => <option key={type} value={type}>{documentNames[type]}</option>)}
              </select>
            </label>
            <label className="auth-field">الملف
              <input type="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" onChange={e => setDocumentFile(e.target.files?.[0] ?? null)}/>
            </label>
            {documentType === 'insurance' && <label className="auth-field">تاريخ انتهاء التأمين
              <input type="date" value={documentExpiry} min={new Date().toISOString().slice(0,10)} onChange={e => setDocumentExpiry(e.target.value)}/>
            </label>}
            <button className="primary-btn" disabled={busy || !documentFile || (documentType === 'insurance' && !documentExpiry)} onClick={submitDriverDocument}>رفع الوثيقة للمراجعة</button>
          </section>}
          {driverProfile && driverProfile.onboarding_status !== 'approved' && <section className="panel">
            <span className="section-kicker">بيانات المركبة</span><h2>أضف مركبتك</h2>
            <label className="auth-field">الشركة المصنعة<input value={vehicleMake} onChange={e => setVehicleMake(e.target.value)} placeholder="مثلاً: Hyundai"/></label>
            <label className="auth-field">الطراز<input value={vehicleModel} onChange={e => setVehicleModel(e.target.value)} placeholder="مثلاً: i20"/></label>
            <label className="auth-field">سنة الصنع<input type="number" value={vehicleYear} onChange={e => setVehicleYear(e.target.value)}/></label>
            <label className="auth-field">اللون<input value={vehicleColor} onChange={e => setVehicleColor(e.target.value)}/></label>
            <label className="auth-field">عدد المقاعد<input type="number" min="2" max="9" value={seatCapacity} onChange={e => setSeatCapacity(e.target.value)}/></label>
            <button className="primary-btn" disabled={busy || !vehicleMake.trim() || !vehicleModel.trim()} onClick={submitVehicle}>إرسال المركبة للمراجعة</button>
          </section>}
          {ratingRide && screen === 'driver' && <RatingPanel ratingStatus={ratingStatus} ratingScore={ratingScore} setRatingScore={setRatingScore} ratingComment={ratingComment} setRatingComment={setRatingComment} busy={busy} submit={submitRating}/>}
          {driverRide && <section className="panel active-driver-ride"><span className="section-kicker">الرحلة النشطة</span><h2>{statusNames[driverRide.status]}</h2><p>{driverRide.pickup_label} ← {driverRide.destination_label}</p><p>الراكب: {driverRide.passenger_name || 'الراكب'}</p><p>الفئة: {categoryNames[driverRide.category] ?? driverRide.category}</p>
            {driverRide.status === 'arrived' && <label className="auth-field">رمز الصعود من الراكب<input inputMode="numeric" maxLength={6} value={boardingPin} onChange={e => setBoardingPin(e.target.value.replace(/\D/g, '').slice(0,6))}/></label>}
            <button className="primary-btn" disabled={busy || (driverRide.status === 'arrived' && boardingPin.length !== 6)} onClick={() => updateDriverRide(driverRide)}>{driverRide.status === 'accepted' ? 'بدء التوجه للراكب' : driverRide.status === 'driver_arriving' ? 'تأكيد الوصول' : driverRide.status === 'arrived' ? 'تأكيد رمز الصعود' : driverRide.status === 'boarded' ? 'بدء الرحلة' : 'إنهاء الرحلة'}</button>
            {['accepted','driver_arriving','arrived'].includes(driverRide.status) && <button className="text-button" disabled={busy} onClick={() => cancelRide(driverRide.id, 'driver_unavailable')}>تعذر إكمال الرحلة · إلغاء</button>}
          </section>}
          <section className="panel">
            <span className="section-kicker">سجل الأرباح</span><h2>الرحلات المكتملة ({driverEarnings.length})</h2>
            <p className="muted">المبالغ أدناه هي أجرة الرحلة الإجمالية المسجلة، وليست صافي مستحقاتك بعد العمولة أو التسوية.</p>
            {!driverEarnings.length && <p className="muted">ستظهر هنا الرحلات المكتملة بعد تنفيذ أول رحلة.</p>}
            {driverEarnings.map(item => <div className="admin-row" key={item.ride_id}>
              <div><b>الصافي: {money(item.driver_net_minor, item.currency_code)}</b><small>الإجمالي {money(item.gross_fare_minor, item.currency_code)} · العمولة {money(item.commission_minor, item.currency_code)} · {item.pickup_label} ← {item.destination_label}</small></div>
              <small>{item.payment_status === 'collected' ? 'تم التحصيل' : 'بانتظار تأكيد التحصيل'} · {time(item.completed_at)}</small>
            </div>)}
          </section>

          <section className="panel">
            <span className="section-kicker">المستحقات والتسويات</span><h2>ملخصك المالي</h2>
            {driverFinance && <>
              <div className="admin-row"><span>إجمالي الأجور</span><b>{money(driverFinance.gross_earned_minor, driverFinance.currency_code)}</b></div>
              <div className="admin-row"><span>عمولات نقدية مستحقة للمنصة</span><b>{money(driverFinance.commission_due_minor, driverFinance.currency_code)}</b></div>
              <div className="admin-row"><span>رصيد قابل للتسوية</span><b>{money(driverFinance.payout_available_minor, driverFinance.currency_code)}</b></div>
              <div className="admin-row"><span>طلبات تسوية قيد المعالجة</span><b>{money(driverFinance.payout_pending_minor, driverFinance.currency_code)}</b></div>
              <label className="field-label">طلب تحويل مستحقاتك (دج)<input className="wide-input" type="number" min="1" value={driverPayoutAmount} onChange={e => setDriverPayoutAmount(e.target.value)} /></label>
              <button className="primary-btn" disabled={busy || !driverFinance.payout_available_minor || !driverPayoutAmount} onClick={requestDriverPayout}>إرسال طلب التسوية</button>
            </>}
          </section>
          <section className="panel offer-card"><span className="section-kicker">العروض الواردة</span><h2>{offers.length} عرض متاح</h2>
            {!offers.length && <p className="muted">ستظهر هنا الطلبات الحقيقية الموجهة إليك عندما تكون معتمداً ومتصلًا وقريبًا من نقطة الانطلاق.</p>}
            {offers.map(offer => <div className="offer-row" key={offer.offer_id}><b>{offer.pickup_label} ← {offer.destination_label}</b><small>{categoryNames[offer.category] ?? offer.category} · {money(offer.proposed_amount_minor, offer.currency_code)}</small><small>ينتهي {time(offer.expires_at)}</small><label className="field-label">أو اقترح سعراً بالدينار<input className="wide-input" type="number" min="1" value={counterAmounts[offer.offer_id] ?? ''} onChange={e => setCounterAmounts(v => ({...v,[offer.offer_id]:e.target.value}))}/></label><div className="offer-buttons"><button className="primary-btn" disabled={busy} onClick={() => acceptOffer(offer.offer_id)}>قبول السعر</button><button className="secondary-btn" disabled={busy} onClick={() => beginFareNegotiation(offer.offer_id)}>إرسال عرض مضاد</button><button className="secondary-btn" disabled={busy} onClick={() => declineOffer(offer.offer_id)}>رفض</button></div></div>)}
          </section>
        </div>}

        {screen === 'admin' && roles.includes('admin') && <div className="admin-grid">
          <section className="panel admin-note"><span className="section-kicker">المراجعة الإدارية</span><h2>الحسابات المعلقة ({accounts.length})</h2>
            <p className="muted">تفعيل الحساب أو اعتماد المركبة هنا مخصص للاختبار فقط ولا يمنح أي رخصة نقل أو تأمين.</p>
            {!accounts.length && <p className="muted">لا توجد حسابات تنتظر التفعيل.</p>}
            {accounts.map(account => <div className="admin-row" key={account.user_id}><div><b>{account.display_name || 'بدون اسم'}</b><small>{account.user_id}</small></div><button className="primary-btn" disabled={busy} onClick={() => reviewAccount(account.user_id)}>تفعيل</button></div>)}
          </section>
          <section className="panel admin-note"><span className="section-kicker">مراقبة الرحلات</span><h2>آخر الرحلات ({adminRides.length})</h2>
            {adminRides.slice(0,12).map(ride => <div className="admin-row" key={ride.ride_id}><div><b>{ride.passenger_name} · {statusNames[ride.ride_status] ?? ride.ride_status}</b><small>{ride.pickup_label} ← {ride.destination_label} · السائق: {ride.driver_name ?? 'لم يُعيّن'} · {money(ride.quoted_amount_minor, ride.currency_code)}</small></div><small>{time(ride.requested_at)}</small></div>)}
          </section>
          <section className="panel admin-note"><span className="section-kicker">خدمة العملاء</span><h2>تذاكر الدعم ({adminSupportTickets.length})</h2>
            {!adminSupportTickets.length && <p className="muted">لا توجد تذاكر دعم حالياً.</p>}
            {adminSupportTickets.map(ticket => <div className="admin-row" key={ticket.ticket_id}><div><b>{ticket.requester_name} · {ticket.category} · {ticket.ticket_status}</b><small>{ticket.initial_message} · {time(ticket.created_at)}</small><textarea rows={2} maxLength={4000} value={adminReplies[ticket.ticket_id] ?? ''} onChange={e => setAdminReplies(items => ({ ...items, [ticket.ticket_id]: e.target.value }))} placeholder="اكتب رد فريق الدعم…"/><div className="admin-review-actions"><button className="secondary-btn" disabled={busy || (adminReplies[ticket.ticket_id] ?? '').trim().length < 2} onClick={() => replySupportTicket(ticket.ticket_id, 'assigned')}>رد · قيد المعالجة</button><button className="primary-btn" disabled={busy || (adminReplies[ticket.ticket_id] ?? '').trim().length < 2} onClick={() => replySupportTicket(ticket.ticket_id, 'resolved')}>رد وحلّ التذكرة</button><button className="secondary-btn" disabled={busy || (adminReplies[ticket.ticket_id] ?? '').trim().length < 2} onClick={() => replySupportTicket(ticket.ticket_id, 'closed')}>رد وإغلاق</button></div></div></div>)}
          </section>
          <section className="panel admin-note"><span className="section-kicker">السلامة والدعم</span><h2>بلاغات السلامة ({safetyReports.length})</h2>
            {!safetyReports.length && <p className="muted">لا توجد بلاغات.</p>}
            {safetyReports.map(report => <div className="admin-row" key={report.report_id}><div><b>{report.severity.toUpperCase()} · {report.reporter_name} · {report.report_status}</b><small>{report.description}</small></div><div className="admin-review-actions"><button className="secondary-btn" disabled={busy} onClick={() => updateSafetyReport(report.report_id,'investigating')}>قيد المراجعة</button><button className="primary-btn" disabled={busy} onClick={() => updateSafetyReport(report.report_id,'resolved')}>تم الحل</button></div></div>)}
          </section>

          <section className="panel admin-note">
            <span className="section-kicker">المالية والعمولات</span><h2>سياسة العمولة</h2>
            <p className="muted">النسبة الحالية: {commissionBps === null ? 'غير مهيأة — يلزم تحديدها قبل إكمال الرحلات' : (commissionBps / 100).toFixed(2) + (commissionProvisional ? '% · نسبة تجريبية مؤقتة' : '% · سياسة معتمدة إدارياً')} · لا تُطبق التغييرات إلا على الرحلات الجديدة المكتملة.</p>
            <label className="field-label">العمولة الجديدة (%)<input className="wide-input" type="number" min="0" max="30" step="0.1" value={commissionDraft} onChange={e => setCommissionDraft(e.target.value)} /></label>
            <button className="primary-btn" disabled={busy} onClick={updatePlatformCommission}>حفظ نسبة العمولة</button>
            <h3>سجل أجور الرحلات ({adminFinancials.length})</h3>
            {!adminFinancials.length && <p className="muted">لا توجد قيود مالية بعد.</p>}
            {adminFinancials.map(finance => <div className="admin-row" key={finance.ride_id}>
              <div><b>{finance.driver_name} · {money(finance.gross_fare_minor, finance.currency_code)}</b><small>عمولة {money(finance.commission_minor, finance.currency_code)} · صافي السائق {money(finance.driver_net_minor, finance.currency_code)} · {finance.payment_status}</small>
                {finance.payment_status === 'pending' && <><input className="wide-input" value={paymentReferences[finance.ride_id] ?? ''} onChange={e => setPaymentReferences(items => ({...items,[finance.ride_id]:e.target.value}))} placeholder="مرجع الإيصال أو التحصيل"/><div className="admin-review-actions"><button className="secondary-btn" disabled={busy} onClick={() => recordRidePayment(finance.ride_id,'cash_to_driver')}>نقداً للسائق</button><button className="primary-btn" disabled={busy} onClick={() => recordRidePayment(finance.ride_id,'manual_transfer_to_platform')}>تحصيل للمنصة</button></div></>}
                {finance.commission_status === 'due' && <><input className="wide-input" value={paymentReferences[finance.ride_id] ?? ''} onChange={e => setPaymentReferences(items => ({...items,[finance.ride_id]:e.target.value}))} placeholder="مرجع تسديد العمولة"/><button className="secondary-btn" disabled={busy} onClick={() => recordCommissionPayment(finance.ride_id)}>تأكيد تسديد العمولة</button></>}
              </div>
            </div>)}
            <h3>طلبات تسوية السائقين ({adminPayouts.length})</h3>
            {!adminPayouts.length && <p className="muted">لا توجد طلبات تسوية.</p>}
            {adminPayouts.map(payout => <div className="admin-row" key={payout.payout_id}>
              <div><b>{payout.driver_name} · {money(payout.amount_minor,payout.currency_code)}</b><small>{payout.payout_status} · {time(payout.requested_at)}{payout.payout_reference ? ' · '+payout.payout_reference : ''}</small>
                {payout.payout_status !== 'paid' && payout.payout_status !== 'rejected' && <><input className="wide-input" value={payoutReferences[payout.payout_id] ?? ''} onChange={e => setPayoutReferences(items => ({...items,[payout.payout_id]:e.target.value}))} placeholder="مرجع التحويل البنكي / البريدي"/><div className="admin-review-actions">{payout.payout_status === 'pending' && <><button className="secondary-btn" disabled={busy} onClick={() => processDriverPayout(payout.payout_id,'approve')}>موافقة</button><button className="secondary-btn" disabled={busy} onClick={() => processDriverPayout(payout.payout_id,'reject')}>رفض</button></>}{payout.payout_status === 'approved' && <button className="primary-btn" disabled={busy} onClick={() => processDriverPayout(payout.payout_id,'pay')}>تأكيد التحويل</button>}</div></>}
              </div>
            </div>)}
          </section>
          <section className="panel admin-note"><span className="section-kicker">مراجعة الوثائق الخاصة</span><h2>وثائق السائقين ({driverDocuments.length})</h2>
            {!driverDocuments.length && <p className="muted">لا توجد وثائق مرفوعة للمراجعة.</p>}
            {driverDocuments.map(doc => <div className="admin-row" key={doc.document_id}><div><b>{doc.display_name || doc.user_id} · {documentNames[doc.document_type] ?? doc.document_type}</b><small>{doc.status === 'approved' ? 'معتمدة' : doc.status === 'rejected' ? 'مرفوضة' : 'قيد المراجعة'} · رُفعت {time(doc.uploaded_at)}{doc.expires_on ? ' · تنتهي ' + doc.expires_on : ''}{doc.review_reason ? ' · ' + doc.review_reason : ''}</small></div><div className="admin-review-actions"><button className="secondary-btn" disabled={busy} onClick={() => previewDriverDocument(doc.object_path!)}>معاينة</button>{doc.status === 'pending' && <><button className="primary-btn" disabled={busy} onClick={() => reviewDriverDocument(doc.document_id,'approved')}>اعتماد</button><button className="secondary-btn" disabled={busy} onClick={() => reviewDriverDocument(doc.document_id,'rejected')}>رفض</button></>}</div></div>)}
            {documentPreviewUrl && <p><a href={documentPreviewUrl} target="_blank" rel="noreferrer">فتح الوثيقة (رابط مؤقت 60 ثانية)</a></p>}
          </section>
          <section className="panel admin-note"><span className="section-kicker">اعتماد السائقين</span><h2>طلبات السائقين ({drivers.length})</h2>
            {!drivers.length && <p className="muted">لا توجد طلبات سائقين.</p>}
            {drivers.map(driver => <div className="admin-row driver-review" key={driver.driver_id}><div><b>{driver.display_name || 'بدون اسم'} · {driver.onboarding_status}</b><small>{driver.vehicle_make ?? 'لا توجد مركبة'} {driver.vehicle_model ?? ''} · {driver.seat_capacity ?? '—'} مقاعد · المركبة: {driver.vehicle_status ?? 'غير مسجلة'}</small></div><div className="admin-review-actions">{driver.vehicle_id && driver.vehicle_status === 'pending' && <><button className="secondary-btn" disabled={busy} onClick={() => reviewVehicle(driver.vehicle_id!, 'approved')}>اعتماد المركبة</button><button className="secondary-btn" disabled={busy} onClick={() => reviewVehicle(driver.vehicle_id!, 'rejected')}>رفض المركبة</button></>}{driver.onboarding_status !== 'approved' && <><button className="primary-btn" disabled={busy || driver.vehicle_status !== 'approved' || driver.account_status !== 'active' || !requiredDocumentTypes.every(type => latestDriverDocumentIsApproved(driverDocuments, driver.driver_id, type))} onClick={() => reviewDriver(driver.driver_id, 'approved')}>اعتماد السائق</button><button className="secondary-btn" disabled={busy} onClick={() => reviewDriver(driver.driver_id, 'rejected')}>رفض السائق</button></>}</div></div>)}
          </section>
        </div>}

        <footer><span>© MITHAQ</span><span><ShieldCheck size={13}/> بيئة اختبار مغلقة · التسويات يدوية ولا يوجد مزود دفع إلكتروني موصول</span></footer>
      </main>
    </div>
  </div>
}


function RatingPanel({ ratingStatus, ratingScore, setRatingScore, ratingComment, setRatingComment, busy, submit }: {
  ratingStatus: RatingStatus | null
  ratingScore: number
  setRatingScore: (value: number) => void
  ratingComment: string
  setRatingComment: (value: string) => void
  busy: boolean
  submit: () => void
}) {
  return <section className="panel rating-panel">
    <span className="section-kicker">تقييم الرحلة</span><h2>كيف كانت تجربتك؟</h2>
    {ratingStatus?.has_rated
      ? <p className="muted">تم إرسال تقييمك: {ratingStatus.score}/5. شكرًا لمساعدتنا على تحسين الخدمة.</p>
      : <>
        <div className="rating-choices">{[1,2,3,4,5].map(score => <button type="button" key={score} className={ratingScore === score ? 'chosen' : ''} onClick={() => setRatingScore(score)}>{score}</button>)}</div>
        <textarea value={ratingComment} onChange={e => setRatingComment(e.target.value)} maxLength={500} placeholder="ملاحظة اختيارية" rows={2}/>
        <button className="primary-btn" disabled={busy} onClick={submit}>إرسال التقييم</button>
      </>}
  </section>
}

function Brand() {
  return <a className="brand" href="#"><span className="brand-mark">م</span><span>MITHAQ</span></a>
}
