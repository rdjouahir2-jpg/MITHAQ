import { Capacitor } from '@capacitor/core'
import { BackgroundGeolocation } from '@capgo/background-geolocation'
import { publicConfig } from './public-config'

type NativeLocation = {
  latitude: number
  longitude: number
  accuracy: number
  time: number | null
  simulated: boolean
}

type LocationCallbacks = {
  onLocation?: (location: NativeLocation) => void
  onError?: (message: string) => void
}

let activeStart: Promise<void> | null = null
let activeToken: string | null = null

const locationEndpoint = `${publicConfig.supabaseUrl}/functions/v1/driver-location`

export function isNativeAndroid(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'android'
}

export async function startDriverBackgroundTracking(
  accessToken: string,
  callbacks: LocationCallbacks = {},
): Promise<boolean> {
  if (!isNativeAndroid()) return false
  if (!accessToken) throw new Error('جلسة الدخول غير صالحة لتشغيل تتبع السائق.')

  const headers = {
    Authorization: `Bearer ${accessToken}`,
    apikey: publicConfig.supabaseAnonKey,
    'Content-Type': 'application/json',
  }

  if (activeStart) {
    if (activeToken !== accessToken) {
      await BackgroundGeolocation.updateHeaders({ headers })
      activeToken = accessToken
    }
    await activeStart
    return true
  }

  activeToken = accessToken
  activeStart = BackgroundGeolocation.start(
    {
      backgroundTitle: 'MITHAQ · تتبع السائق',
      backgroundMessage: 'موقعك يُشارك مع الراكب المرتبط برحلتك أو مع نظام المطابقة أثناء تفعيل التوفر.',
      requestPermissions: true,
      stale: false,
      distanceFilter: 15,
      minIntervalMs: 15000,
      url: locationEndpoint,
      headers,
    },
    (location, error) => {
      if (error) {
        callbacks.onError?.(error.message || 'تعذر تشغيل خدمة الموقع.')
        return
      }
      if (!location) return
      if (location.accuracy > 100 || location.simulated === true) return
      callbacks.onLocation?.(location)
    },
  ).catch(error => {
    activeStart = null
    activeToken = null
    throw error
  })

  await activeStart
  return true
}

export async function refreshDriverBackgroundTrackingToken(accessToken: string): Promise<void> {
  if (!isNativeAndroid() || !accessToken) return
  if (activeStart) {
    await BackgroundGeolocation.updateHeaders({
      headers: {
        Authorization: `Bearer ${accessToken}`,
        apikey: publicConfig.supabaseAnonKey,
        'Content-Type': 'application/json',
      },
    })
    activeToken = accessToken
  }
}

export async function stopDriverBackgroundTracking(): Promise<void> {
  if (!isNativeAndroid()) return
  await BackgroundGeolocation.stop()
  activeStart = null
  activeToken = null
}
