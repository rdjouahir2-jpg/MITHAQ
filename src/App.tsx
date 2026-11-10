import { useMemo, useState } from 'react'
import { ArrowLeftRight, CarFront, Check, ChevronDown, CircleHelp, Clock3, MapPin, Menu, Navigation, ShieldCheck, Sparkles, Star, Wallet, X } from 'lucide-react'

type Mode = 'passenger' | 'driver' | 'admin'
type RideStatus = 'idle' | 'searching' | 'accepted' | 'arrived' | 'started' | 'completed' | 'cancelled'

const money = (n: number) => new Intl.NumberFormat('fr-DZ').format(n) + ' دج'
const steps: { key: RideStatus; label: string }[] = [
  { key: 'searching', label: 'نبحث عن سائق' },
  { key: 'accepted', label: 'تم قبول الرحلة' },
  { key: 'arrived', label: 'السائق وصل' },
  { key: 'started', label: 'الرحلة جارية' },
  { key: 'completed', label: 'اكتملت الرحلة' },
]

export default function App() {
  const [mode, setMode] = useState<Mode>('passenger')
  const [from, setFrom] = useState('وسط المدينة')
  const [to, setTo] = useState('الجامعة')
  const [category, setCategory] = useState('اقتصادية')
  const [status, setStatus] = useState<RideStatus>('idle')
  const [offer, setOffer] = useState('600')
  const [notice, setNotice] = useState('')
  const [menuOpen, setMenuOpen] = useState(false)
  const [online, setOnline] = useState(false)

  const estimate = useMemo(() => {
    const base = category === 'مريحة' ? 850 : category === 'عائلية' ? 1100 : 500
    return base + Math.max(0, from.length + to.length - 15) * 12
  }, [category, from, to])

  const reset = () => { setStatus('idle'); setNotice('') }
  const progress = steps.findIndex(s => s.key === status)

  return <div className="app-shell">
    <header className="topbar">
      <button className="icon-btn mobile-menu" onClick={() => setMenuOpen(!menuOpen)} aria-label="القائمة"><Menu size={21}/></button>
      <a className="brand" href="#"><span className="brand-mark">م</span><span>MITHAQ</span></a>
      <div className="top-actions">
        <span className="secure-label"><ShieldCheck size={15}/> تنقّل بثقة</span>
        <button className="avatar" onClick={() => setNotice('الملف الشخصي التجريبي — لم يتم إنشاء حساب بعد')}>م</button>
      </div>
    </header>

    <div className="layout">
      <aside className={menuOpen ? 'sidebar open' : 'sidebar'}>
        <div className="side-caption">مساحة العمل</div>
        {(['passenger','driver','admin'] as Mode[]).map(m => <button key={m} className={mode === m ? 'nav-item active' : 'nav-item'} onClick={() => { setMode(m); setMenuOpen(false); setNotice('') }}>
          {m === 'passenger' ? <MapPin size={18}/> : m === 'driver' ? <CarFront size={18}/> : <ShieldCheck size={18}/>}
          {m === 'passenger' ? 'اطلب رحلة' : m === 'driver' ? 'مساحة السائق' : 'الإدارة'}
        </button>)}
        <div className="side-bottom"><div className="help-card"><CircleHelp size={19}/><b>تحتاج مساعدة؟</b><p>هذه نسخة تجريبية. لا يوجد دعم طوارئ مباشر بعد.</p></div><small>الإصدار التجريبي 0.1</small></div>
      </aside>

      <main className="main">
        <div className="welcome-row"><div><div className="eyebrow">MITHAQ · الجزائر</div><h1>{mode === 'passenger' ? 'إلى أين نذهب اليوم؟' : mode === 'driver' ? 'مساحة السائق' : 'مركز العمليات'}</h1><p>{mode === 'passenger' ? 'رحلتك تبدأ بخطوات واضحة.' : mode === 'driver' ? 'تابع حالة التوفر والطلبات التجريبية.' : 'نظرة أولية على حالة المنصة التجريبية.'}</p></div><div className="location-pill"><span className="pulse"></span> وضع تجريبي</div></div>

        {notice && <div className="notice"><span>{notice}</span><button onClick={() => setNotice('')}><X size={16}/></button></div>}

        {mode === 'passenger' && <div className="content-grid">
          <section className="panel booking-panel">
            <div className="panel-heading"><div><span className="section-kicker">احجز مشوارك</span><h2>حدد تفاصيل الرحلة</h2></div><span className="heading-icon"><Navigation size={20}/></span></div>
            <div className="route-fields">
              <label className="field"><span className="field-dot green"></span><span className="field-body"><small>نقطة الانطلاق</small><input value={from} onChange={e => setFrom(e.target.value)} placeholder="أين نلتقي؟"/></span></label>
              <button className="swap-btn" onClick={() => {setFrom(to);setTo(from)}} aria-label="تبديل"><ArrowLeftRight size={17}/></button>
              <label className="field"><span className="field-dot red"></span><span className="field-body"><small>الوجهة</small><input value={to} onChange={e => setTo(e.target.value)} placeholder="إلى أين؟"/></span></label>
            </div>
            <div className="field-label">اختر فئة المركبة</div>
            <div className="categories">{['اقتصادية','مريحة','عائلية'].map((c,i)=><button key={c} onClick={()=>setCategory(c)} className={category===c?'category selected':'category'}><CarFront size={21}/><b>{c}</b><small>{i===0?'للتنقل اليومي':i===1?'راحة إضافية':'مساحة أكبر'}</small></button>)}</div>
            <div className="fare-box"><div><small>السعر التقديري</small><strong>{money(estimate)}</strong><span>قابل للتأكيد قبل إرسال الطلب</span></div><div className="fare-icon"><Wallet size={22}/></div></div>
            <button className="primary-btn" disabled={!from.trim() || !to.trim() || status !== 'idle'} onClick={()=>{setStatus('searching');setNotice('طلب تجريبي فقط — لم يتم إرسال سائق حقيقي')}}>اطلب رحلة <span>←</span></button>
            <p className="microcopy"><ShieldCheck size={14}/> لن تتم أي عملية دفع في هذه النسخة التجريبية.</p>
          </section>

          <section className="panel map-panel">
            <div className="map-top"><span className="map-tag"><MapPin size={14}/> خريطة توضيحية</span><span className="map-muted">ليست GPS حقيقياً</span></div>
            <div className="map-art"><div className="map-grid"></div><div className="road road-a"></div><div className="road road-b"></div><div className="road road-c"></div><div className="route-line"></div><div className="pin pin-start"><span></span></div><div className="pin pin-end"><span></span></div><div className="map-label label-start">{from || 'الانطلاق'}</div><div className="map-label label-end">{to || 'الوجهة'}</div><div className="map-center"><Navigation size={17}/></div></div>
            <div className="map-footer"><div><small>المسار</small><b>{from} ← {to}</b></div><div className="duration"><Clock3 size={15}/> تقديري</div></div>
          </section>
        </div>}

        {mode === 'passenger' && status !== 'idle' && <section className="panel trip-panel"><div className="trip-head"><div><span className="section-kicker">حالة الطلب</span><h2>{steps.find(s=>s.key===status)?.label || 'الطلب ملغى'}</h2></div><span className="trip-badge">تجربة محلية</span></div><div className="progress">{steps.map((s,i)=><div className={i<=progress?'progress-step done':'progress-step'} key={s.key}><span>{i<progress?<Check size={13}/>:i+1}</span><small>{s.label}</small></div>)}</div><div className="demo-actions">{status==='searching' && <button className="primary-btn" onClick={()=>setStatus('accepted')}>محاكاة قبول سائق</button>}{status==='accepted' && <button className="primary-btn" onClick={()=>setStatus('arrived')}>محاكاة وصول السائق</button>}{status==='arrived' && <button className="primary-btn" onClick={()=>setStatus('started')}>تأكيد الصعود التجريبي</button>}{status==='started' && <button className="primary-btn" onClick={()=>setStatus('completed')}>إنهاء الرحلة التجريبية</button>}{(status==='completed'||status==='cancelled') && <button className="primary-btn" onClick={reset}>طلب رحلة جديدة</button>}<button className="text-btn" onClick={()=>setStatus('cancelled')}>إلغاء التجربة</button></div></section>}

        {mode === 'driver' && <section className="driver-grid"><div className="panel driver-status"><span className="section-kicker">حالة الحساب</span><h2>{online?'أنت متصل (تجريبي)':'أنت غير متصل'}</h2><p>فعّل التوفر لاستكشاف تجربة استقبال الطلبات.</p><button className={online?'secondary-btn':'primary-btn'} onClick={()=>setOnline(!online)}>{online?'إيقاف التوفر':'تفعيل التوفر'}</button><div className="driver-note"><ShieldCheck size={17}/> لا يمكن استقبال رحلات حقيقية قبل التحقق من السائق والمركبة.</div></div><div className="panel offer-card"><span className="section-kicker">عرض توضيحي</span><h2>طلب رحلة تجريبي</h2><div className="offer-route"><span>وسط المدينة</span><span>الجامعة</span></div><div className="offer-meta"><span><Clock3 size={15}/> 12 دقيقة تقريباً</span><b>{money(Number(offer)||0)}</b></div><label className="field-label">قيمة العرض التجريبي (دج)<input className="offer-input" inputMode="numeric" value={offer} onChange={e=>setOffer(e.target.value.replace(/[^0-9]/g,''))}/></label><button className="primary-btn" disabled={!online} onClick={()=>setNotice('تم قبول العرض في المحاكاة فقط؛ لا توجد رحلة فعلية')}>قبول الطلب التجريبي</button></div></section>}

        {mode === 'admin' && <section className="admin-grid"><div className="stat-card"><span>الرحلات الحقيقية</span><b>0</b><small>لم يتم الإطلاق</small></div><div className="stat-card"><span>السائقون المعتمدون</span><b>0</b><small>لا توجد ملفات حقيقية</small></div><div className="stat-card"><span>بلاغات السلامة</span><b>0</b><small>بيئة تجريبية</small></div><div className="panel admin-note"><ShieldCheck size={22}/><h2>لوحة إدارة أولية</h2><p>ستضاف إدارة المستخدمين والسائقين والرحلات والصلاحيات وسجل التدقيق بعد ربط قاعدة البيانات. لا توجد بيانات حقيقية في هذه النسخة.</p></div></section>}

        <footer><span>© MITHAQ 2026</span><span><ShieldCheck size={13}/> بيانات تجريبية · لا رحلات أو مدفوعات حقيقية</span></footer>
      </main>
    </div>
  </div>
}
