import type { ReactNode } from 'react';
import { motion } from 'framer-motion';
import {
  Bike, Car, ShoppingBag, CalendarClock, MessageSquare, ShieldCheck,
  Wallet, MapPin, BadgeCheck, Ban, ArrowUpRight, Mail,
} from 'lucide-react';

const reveal = {
  hidden: { opacity: 0, y: 28 },
  show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: [0.22, 1, 0.36, 1] as const } },
};

function Section({ id, children, className = '' }: { id: string; children: ReactNode; className?: string }) {
  return (
    <section id={id} className={`relative w-full scroll-mt-20 px-5 py-20 sm:px-8 sm:py-28 ${className}`}>
      <div className="mx-auto max-w-7xl">{children}</div>
    </section>
  );
}

function Heading({ eyebrow, title, sub }: { eyebrow: string; title: string; sub?: string }) {
  return (
    <motion.div variants={reveal} initial="hidden" whileInView="show" viewport={{ once: true, margin: '-80px' }}>
      <p className="text-xs uppercase tracking-tight text-brand">{eyebrow}</p>
      <h2 className="mt-2 max-w-3xl text-3xl font-medium tracking-tight text-white sm:text-5xl">{title}</h2>
      {sub && <p className="mt-4 max-w-2xl text-sm text-white/60 sm:text-base">{sub}</p>}
    </motion.div>
  );
}

const SERVICES = [
  { icon: Bike, title: 'Bike', desc: 'Standard & Electric bikes for quick, affordable city hops.' },
  { icon: Car, title: 'Car', desc: 'Economy, Comfort and SUV rides for any occasion.' },
  { icon: ShoppingBag, title: 'Errands', desc: 'Groceries, parcels, pharmacy, documents and more.' },
  { icon: CalendarClock, title: 'Schedule', desc: 'Book a trip ahead for the exact time you need it.' },
  { icon: MessageSquare, title: 'In-app Chat', desc: 'Safe text-only chat with automatic moderation.' },
  { icon: ShieldCheck, title: 'Escrow Pay', desc: 'Pay 50% to confirm, the rest after your trip completes.' },
];

const FARES = [
  { name: 'Standard Bike', min: 120 },
  { name: 'Electric Bike', min: 150 },
  { name: 'Economy', min: 300 },
  { name: 'Comfort', min: 450 },
  { name: 'SUV', min: 600 },
  { name: 'Errands', min: 300 },
];

const SAFETY = [
  { icon: BadgeCheck, text: 'Every rider is ID, licence & insurance verified before activation.' },
  { icon: MapPin, text: 'Real-time GPS tracking on every single trip.' },
  { icon: MessageSquare, text: 'Text-only chat with AI moderation — no numbers, no abuse.' },
  { icon: Wallet, text: 'Secure Paystack payments — no cash, no manual transfers.' },
  { icon: Ban, text: 'Fraud detection on fare adjustments (max +30%, valid reasons only).' },
];

export default function Sections({ onDownload }: { onDownload: () => void }) {
  return (
    <>
      {/* ABOUT */}
      <Section id="about" className="border-t border-white/10 bg-black">
        <div className="grid items-center gap-10 lg:grid-cols-2">
          <Heading
            eyebrow="About U-Bike"
            title="Move Better. Earn More."
            sub="U-Bike is a Kenyan ride-hailing and errands platform connecting riders and customers with safe, affordable and reliable transport. Riders keep 80% of every trip and get paid to M-Pesa in 24–48 hours."
          />
          <motion.div
            className="grid grid-cols-3 gap-4"
            variants={reveal}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, margin: '-80px' }}
          >
            {[
              { k: '20%', v: 'platform fee only' },
              { k: '80%', v: 'goes to riders' },
              { k: '24–48h', v: 'M-Pesa payouts' },
            ].map((s) => (
              <div key={s.k} className="rounded-2xl border border-white/10 bg-white/[0.03] p-5 text-center">
                <div className="text-2xl font-bold text-brand sm:text-3xl">{s.k}</div>
                <div className="mt-1 text-xs text-white/50">{s.v}</div>
              </div>
            ))}
          </motion.div>
        </div>
      </Section>

      {/* SERVICES */}
      <Section id="services" className="bg-black">
        <Heading eyebrow="What we offer" title="One app, every way to move." />
        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {SERVICES.map((s, i) => (
            <motion.div
              key={s.title}
              className="rounded-2xl border border-white/10 bg-white/[0.03] p-7 transition hover:border-brand/50"
              variants={reveal}
              initial="hidden"
              whileInView="show"
              viewport={{ once: true, margin: '-60px' }}
              transition={{ delay: i * 0.06 }}
            >
              <s.icon className="h-8 w-8 text-brand" />
              <h3 className="mt-4 text-lg font-semibold text-white">{s.title}</h3>
              <p className="mt-1 text-sm text-white/60">{s.desc}</p>
            </motion.div>
          ))}
        </div>
      </Section>

      {/* PRICING */}
      <Section id="pricing" className="border-t border-white/10 bg-black">
        <Heading
          eyebrow="Pricing"
          title="Transparent minimum fares."
          sub="Final fares depend on distance, time and conditions — calculated fairly for every trip."
        />
        <div className="mt-12 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
          {FARES.map((f, i) => (
            <motion.div
              key={f.name}
              className="rounded-2xl border border-white/10 bg-white/[0.03] p-5 text-center"
              variants={reveal}
              initial="hidden"
              whileInView="show"
              viewport={{ once: true, margin: '-60px' }}
              transition={{ delay: i * 0.05 }}
            >
              <div className="text-sm font-medium text-white">{f.name}</div>
              <div className="mt-2 text-3xl font-bold text-brand">{f.min}</div>
              <div className="text-xs text-white/40">KES min</div>
            </motion.div>
          ))}
        </div>
      </Section>

      {/* SAFETY */}
      <Section id="safety" className="bg-black">
        <div className="grid items-center gap-10 lg:grid-cols-2">
          <div>
            <Heading eyebrow="Safety" title="Safety first, always." />
            <ul className="mt-8 space-y-4">
              {SAFETY.map((s) => (
                <motion.li
                  key={s.text}
                  className="flex items-start gap-3 text-white/70"
                  variants={reveal}
                  initial="hidden"
                  whileInView="show"
                  viewport={{ once: true, margin: '-40px' }}
                >
                  <s.icon className="mt-0.5 h-5 w-5 shrink-0 text-leaf" />
                  <span className="text-sm sm:text-base">{s.text}</span>
                </motion.li>
              ))}
            </ul>
          </div>
          <motion.div
            className="rounded-3xl bg-gradient-to-br from-brand to-[#0B6FA4] p-10"
            variants={reveal}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, margin: '-60px' }}
          >
            <ShieldCheck className="h-14 w-14 text-white" />
            <h3 className="mt-5 text-2xl font-bold text-white">Built for trust</h3>
            <p className="mt-2 text-white/85">
              We're committed to a safe and secure community for riders and customers alike.
            </p>
          </motion.div>
        </div>
      </Section>

      {/* RIDERS */}
      <Section id="riders" className="border-t border-white/10 bg-black">
        <motion.div
          className="overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-br from-white/[0.06] to-transparent p-10 text-center sm:p-16"
          variants={reveal}
          initial="hidden"
          whileInView="show"
          viewport={{ once: true, margin: '-60px' }}
        >
          <p className="text-xs uppercase tracking-tight text-leaf">Founding Riders Program</p>
          <h2 className="mx-auto mt-3 max-w-2xl text-3xl font-medium tracking-tight text-white sm:text-5xl">
            Become a U-Bike Rider.
          </h2>
          <p className="mx-auto mt-4 max-w-xl text-sm text-white/60 sm:text-base">
            Keep 80% of every trip and get paid to your M-Pesa in 24–48 hours.{' '}
            <span className="font-semibold text-leaf">The first 10 bike & 10 car riders register free.</span>
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3">
            <button onClick={onDownload} className="rounded-full bg-leaf px-6 py-3 text-sm font-semibold text-black transition hover:opacity-90">
              Download Bike Rider App
            </button>
            <button onClick={onDownload} className="rounded-full bg-brand px-6 py-3 text-sm font-semibold text-white transition hover:opacity-90">
              Download Car Rider App
            </button>
            <button onClick={onDownload} className="rounded-full border border-white/20 px-6 py-3 text-sm font-semibold text-white transition hover:bg-white/10">
              Errands Rider App
            </button>
          </div>
        </motion.div>
      </Section>

      {/* DOWNLOAD + CONTACT / FOOTER */}
      <Section id="contact" className="border-t border-white/10 bg-black">
        <div id="download" className="grid gap-10 lg:grid-cols-2">
          <Heading
            eyebrow="Get started"
            title="Download the app & ride today."
            sub="Available on Android. Reach out any time — we're here to help."
          />
          <div className="flex flex-col justify-center gap-4">
            <button onClick={onDownload} className="group inline-flex w-fit items-center gap-2 rounded-full bg-white px-7 py-4 text-sm font-semibold text-black transition hover:bg-white/90">
              Download All Apps
              <ArrowUpRight className="h-4 w-4 transition-transform group-hover:translate-x-1 group-hover:-translate-y-0.5" />
            </button>
            <a href="mailto:support@ubike.co.ke" className="inline-flex w-fit items-center gap-2 text-sm text-white/70 transition hover:text-white">
              <Mail className="h-4 w-4" /> support@ubike.co.ke
            </a>
          </div>
        </div>

        <div className="mt-16 flex flex-col items-center justify-between gap-3 border-t border-white/10 pt-6 text-xs text-white/50 sm:flex-row">
          <span>© 2026 U-Bike. Move Better. Earn More.</span>
          <div className="flex gap-5">
            <a href="#" className="hover:text-white">Terms</a>
            <a href="#" className="hover:text-white">Privacy</a>
            <span>Secured by Paystack · Kenya</span>
          </div>
        </div>
      </Section>
    </>
  );
}
