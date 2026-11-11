import { useCallback, useEffect, useMemo, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import {
  CarFront, CircleHelp, LogOut,
  MapPin, Navigation, RefreshCw, ShieldCheck, UserRound, Wallet,
} from 'lucide-react'
import MapPicker, { type GeoPoint } from './components/MapPicker'
import { isSupabaseConfigured, supabase } from './lib/supabase'
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
type RatingStatus = { has_rated: boolean; score: number | null; comment: string | null }
type DriverEarning = { ride_id: string; pickup_label: string; destination_label: string; completed_at: string; gross_fare_minor: number; currency_code: string }
type AdminDriver = {
  driver_id: string; user_id: string; display_name: string; account_status: string
  onboarding_status: string; vehicle_id: string | null; vehicle_make: string | null
  vehicle_model: string | null; vehicle_year: number | null; vehicle_color: string | null
  seat_capacity: number | null; vehicle_status: string | null
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
  const [offers, setOffers] = useState<Offer[]>([])
  const [negotiations, setNegotiations] = useState<FareNegotiation[]>([])
  const [counterAmounts, setCounterAmounts] = useState<Record<string, string>>({})
  const [accounts, setAccounts] = useState<AdminAccount[]>([])
  const [drivers, setDrivers] = useState<AdminDriver[]>([])
  const [adminRides, setAdminRides] = useState<AdminRide[]>([])
  const [safetyReports, setSafetyReports] = useState<SafetyReport[]>([])
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
    const [profileResult, roleResult, ridesResult, driverResult] = await Promise.all([
      supabase.from('profiles').select('id,display_name,account_status').eq('id', userId).maybeSingle(),
      supabase.from('user_roles').select('role').eq('user_id', userId),
      supabase.rpc('get_my_passenger_ride_details', { p_limit: 20 }),
      supabase.from('driver_profiles').select('id,onboarding_status,availability_status').eq('user_id', userId).maybeSingle(),
    ])
    if (profileResult.error) throw profileResult.error
    if (roleResult.error) throw roleResult.error
    if (ridesResult.error) throw ridesResult.error
    setProfile(profileResult.data as Profile | null)
    const nextRoles = (roleResult.data ?? []).map(row => row.role as string)
    setRoles(nextRoles)
    setPassengerRides((ridesResult.data ?? []) as Ride[])
    setDriverProfile(driverResult.data as DriverProfile | null)
    setDriverOnline(driverResult.data?.availability_status === 'online')
    const negotiationRows = await getMyFareNegotiations()
    setNegotiations(negotiationRows)

    if (driverResult.data) {
      const [offersResult, driverRidesResult, earningsResult] = await Promise.all([
        supabase.rpc('get_my_driver_offers'),
        supabase.rpc('get_my_driver_ride_details', { p_limit: 20 }),
        supabase.rpc('get_my_driver_earnings', { p_limit: 20 }),
      ])
      if (offersResult.error) throw offersResult.error
      if (driverRidesResult.error) throw driverRidesResult.error
      if (earningsResult.error) throw earningsResult.error
      setOffers((offersResult.data ?? []) as Offer[])
      setDriverRides((driverRidesResult.data ?? []) as Ride[])
      setDriverEarnings((earningsResult.data ?? []) as DriverEarning[])
    } else {
      setOffers([])
      setDriverRides([])
      setDriverEarnings([])
    }

    if (nextRoles.includes('admin')) {
      const [accountResult, driverQueueResult, rideResult, safetyResult] = await Promise.all([
        supabase.rpc('admin_list_pending_accounts'),
        supabase.rpc('admin_list_driver_applications'),
        supabase.rpc('admin_list_recent_rides'),
        supabase.rpc('admin_list_safety_reports'),
      ])
      if (accountResult.error) throw accountResult.error
      if (driverQueueResult.error) throw driverQueueResult.error
      if (rideResult.error) throw rideResult.error
      if (safetyResult.error) throw safetyResult.error
      setAdminRides((rideResult.data ?? []) as AdminRide[])
      setSafetyReports((safetyResult.data ?? []) as SafetyReport[])
      setAccounts((accountResult.data ?? []) as AdminAccount[])
      setDrivers((driverQueueResult.data ?? []) as AdminDriver[])
    } else {
      setAccounts([])
      setDrivers([])
      setAdminRides([])
      setSafetyReports([])
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
        setProfile(null); setRoles([]); setDriverProfile(null)
        setPassengerRides([]); setDriverRides([]); setOffers([]); setNegotiations([])
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
    if (!driverProfile || !['online','busy'].includes(driverProfile.availability_status)) return
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
    // A foreground heartbeat refreshes the fix even when the vehicle is stationary.
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
      } catch (locationError) {
        await setDriverAvailability(false)
        throw locationError
      }
      setDriverOnline(true)
      setDriverProfile(current => current ? { ...current, availability_status: 'online' } : current)
      await refreshData(user!.id)
      setNotice('أصبحت متاحًا. سيُحدّث الهاتف موقعك أثناء بقاء التطبيق مفتوحًا.')
    } else {
      await setDriverAvailability(false)
      await refreshData(user!.id)
      setNotice('أصبحت غير متاح.')
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

  const updateSafetyReport = (reportId: string, status: 'investigating' | 'resolved' | 'closed') => run(async () => {
    const { error: reportError } = await supabase!.rpc('admin_update_safety_report', {
      p_report_id: reportId, p_status: status,
      p_reason: status === 'investigating' ? 'بدأت مراجعة البلاغ.' : status === 'resolved' ? 'تمت مراجعة البلاغ وحلّه في بيئة الاختبار.' : 'أُغلق البلاغ بعد المراجعة.',
    })
    if (reportError) throw reportError
    await refreshData(user!.id)
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
              <div><b>{money(item.gross_fare_minor, item.currency_code)}</b><small>{item.pickup_label} ← {item.destination_label}</small></div>
              <small>{time(item.completed_at)}</small>
            </div>)}
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
          <section className="panel admin-note"><span className="section-kicker">السلامة والدعم</span><h2>بلاغات السلامة ({safetyReports.length})</h2>
            {!safetyReports.length && <p className="muted">لا توجد بلاغات.</p>}
            {safetyReports.map(report => <div className="admin-row" key={report.report_id}><div><b>{report.severity.toUpperCase()} · {report.reporter_name} · {report.report_status}</b><small>{report.description}</small></div><div className="admin-review-actions"><button className="secondary-btn" disabled={busy} onClick={() => updateSafetyReport(report.report_id,'investigating')}>قيد المراجعة</button><button className="primary-btn" disabled={busy} onClick={() => updateSafetyReport(report.report_id,'resolved')}>تم الحل</button></div></div>)}
          </section>
          <section className="panel admin-note"><span className="section-kicker">اعتماد السائقين</span><h2>طلبات السائقين ({drivers.length})</h2>
            {!drivers.length && <p className="muted">لا توجد طلبات سائقين.</p>}
            {drivers.map(driver => <div className="admin-row driver-review" key={driver.driver_id}><div><b>{driver.display_name || 'بدون اسم'} · {driver.onboarding_status}</b><small>{driver.vehicle_make ?? 'لا توجد مركبة'} {driver.vehicle_model ?? ''} · {driver.seat_capacity ?? '—'} مقاعد · المركبة: {driver.vehicle_status ?? 'غير مسجلة'}</small></div><div className="admin-review-actions">{driver.vehicle_id && driver.vehicle_status === 'pending' && <><button className="secondary-btn" disabled={busy} onClick={() => reviewVehicle(driver.vehicle_id!, 'approved')}>اعتماد المركبة</button><button className="secondary-btn" disabled={busy} onClick={() => reviewVehicle(driver.vehicle_id!, 'rejected')}>رفض المركبة</button></>}{driver.onboarding_status !== 'approved' && <><button className="primary-btn" disabled={busy || driver.vehicle_status !== 'approved' || driver.account_status !== 'active'} onClick={() => reviewDriver(driver.driver_id, 'approved')}>اعتماد السائق</button><button className="secondary-btn" disabled={busy} onClick={() => reviewDriver(driver.driver_id, 'rejected')}>رفض السائق</button></>}</div></div>)}
          </section>
        </div>}

        <footer><span>© MITHAQ</span><span><ShieldCheck size={13}/> بيئة اختبار مغلقة · لا مدفوعات أو رحلات تجارية</span></footer>
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
