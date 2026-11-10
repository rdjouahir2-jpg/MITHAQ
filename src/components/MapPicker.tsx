import { useEffect, useRef } from 'react'
import { Map as MapLibreMap, Marker, NavigationControl, type GeoJSONSource } from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'

export type GeoPoint = { latitude: number; longitude: number }
type Props = {
  pickup: GeoPoint | null
  destination: GeoPoint | null
  driverLocation?: GeoPoint | null
  routeCoordinates?: [number, number][] | null
  selection: 'pickup' | 'destination'
  onSelect: (point: GeoPoint) => void
  onLocate: (point: GeoPoint) => void
}

export default function MapPicker({
  pickup, destination, driverLocation, routeCoordinates, selection, onSelect, onLocate,
}: Props) {
  const container = useRef<HTMLDivElement>(null)
  const map = useRef<MapLibreMap | null>(null)
  const markers = useRef<{ pickup?: Marker; destination?: Marker; driver?: Marker }>({})
  const selectRef = useRef(onSelect)
  const routeRef = useRef(routeCoordinates)
  selectRef.current = onSelect
  routeRef.current = routeCoordinates

  useEffect(() => {
    if (!container.current || map.current) return
    const instance = new MapLibreMap({
      container: container.current,
      style: 'https://tiles.openfreemap.org/styles/liberty',
      center: [3.9, 36.3],
      zoom: 5.2,
      attributionControl: true,
      cooperativeGestures: true,
    })
    map.current = instance
    instance.addControl(new NavigationControl({ showCompass: false }), 'top-right')
    instance.on('load', () => {
      if (!instance.getSource('mithaq-route')) {
        instance.addSource('mithaq-route', {
          type: 'geojson',
          data: { type: 'FeatureCollection', features: [] },
        })
        instance.addLayer({
          id: 'mithaq-route-line', type: 'line', source: 'mithaq-route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#24885b', 'line-width': 5, 'line-opacity': 0.88 },
        })
      }
      const source = instance.getSource('mithaq-route') as GeoJSONSource
      source.setData({
        type: 'FeatureCollection',
        features: routeRef.current?.length ? [{
          type: 'Feature', properties: {},
          geometry: { type: 'LineString', coordinates: routeRef.current },
        }] : [],
      })
    })
    instance.on('click', event => {
      selectRef.current({ latitude: event.lngLat.lat, longitude: event.lngLat.lng })
    })
    instance.on('error', event => {
      if (event.error) console.warn('MapLibre:', event.error.message)
    })
    return () => {
      Object.values(markers.current).forEach(marker => marker?.remove())
      markers.current = {}
      instance.remove()
      map.current = null
    }
  }, [])

  useEffect(() => {
    const instance = map.current
    if (!instance) return
    const update = (key: 'pickup' | 'destination' | 'driver', point: GeoPoint | null | undefined, color: string, label: string) => {
      const existing = markers.current[key]
      if (!point) {
        existing?.remove()
        delete markers.current[key]
        return
      }
      if (existing) {
        existing.setLngLat([point.longitude, point.latitude])
        return
      }
      const element = document.createElement('div')
      element.className = `mithaq-map-marker ${key}`
      element.title = label
      element.style.backgroundColor = color
      markers.current[key] = new Marker({ element, anchor: 'bottom' })
        .setLngLat([point.longitude, point.latitude])
        .addTo(instance)
    }
    update('pickup', pickup, '#24885b', 'نقطة الانطلاق')
    update('destination', destination, '#d66e58', 'الوجهة')
    update('driver', driverLocation, '#2465bd', 'موقع السائق')
  }, [pickup, destination, driverLocation])

  useEffect(() => {
    const source = map.current?.getSource('mithaq-route') as GeoJSONSource | undefined
    if (!source) return
    source.setData({
      type: 'FeatureCollection',
      features: routeCoordinates?.length ? [{
        type: 'Feature', properties: {},
        geometry: { type: 'LineString', coordinates: routeCoordinates },
      }] : [],
    })
  }, [routeCoordinates])

  const locate = () => {
    if (!navigator.geolocation) {
      alert('تحديد الموقع غير مدعوم في هذا المتصفح.')
      return
    }
    navigator.geolocation.getCurrentPosition(
      position => {
        const point = { latitude: position.coords.latitude, longitude: position.coords.longitude }
        map.current?.flyTo({ center: [point.longitude, point.latitude], zoom: 15, essential: true })
        onLocate(point)
      },
      error => alert(error.code === 1 ? 'اسمح للمتصفح باستخدام الموقع.' : 'تعذر تحديد موقعك. حاول مجدداً.'),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 5000 },
    )
  }

  return <div className="real-map-wrap">
    <div ref={container} className="real-map" aria-label="خريطة اختيار نقاط الرحلة" />
    <div className="map-picker-toolbar">
      <span>اضغط على الخريطة لتحديد {selection === 'pickup' ? 'الانطلاق' : 'الوجهة'}</span>
      <button type="button" onClick={locate}>موقعي الحالي</button>
    </div>
  </div>
}
