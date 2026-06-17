import { useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowUpRight, Menu, X } from 'lucide-react';
import ShinyText from './components/ShinyText';

const NAV_LINKS = ['Home', 'About', 'Services', 'Pricing', 'Safety', 'Riders', 'Contact'];

// Replace with a U-Bike-branded clip when available.
const HERO_VIDEO =
  'https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260328_105406_16f4600d-7a92-4292-b96e-b19156c7830a.mp4';

const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  show: (i = 0) => ({
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, delay: 0.15 * i, ease: [0.22, 1, 0.36, 1] as const },
  }),
};

export default function App() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <main className="relative h-screen w-full overflow-hidden bg-black font-sans text-white">
      {/* Background video */}
      <video
        className="absolute inset-0 h-full w-full object-cover"
        src={HERO_VIDEO}
        autoPlay
        loop
        muted
        playsInline
        poster="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E"
      />
      <div className="absolute inset-0 bg-black/55" />
      <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/70" />

      {/* Foreground */}
      <div className="relative z-10 flex h-full flex-col">
        {/* Nav */}
        <header className="mx-auto w-full max-w-7xl px-5 py-5 sm:px-8">
          <nav className="flex items-center justify-between">
            <motion.a
              href="#"
              className="flex items-center gap-2"
              variants={fadeUp}
              initial="hidden"
              animate="show"
            >
              <span className="flex h-7 w-7 items-center justify-center rounded-full border-2 border-white">
                <span className="h-2.5 w-2.5 rounded-full bg-white" />
              </span>
              <span className="text-lg font-semibold tracking-tight">U-Bike</span>
            </motion.a>

            <motion.div
              className="hidden items-center rounded-full border border-gray-700 px-2 py-1.5 lg:flex"
              variants={fadeUp}
              initial="hidden"
              animate="show"
              custom={0.5}
            >
              {NAV_LINKS.map((link) => (
                <a
                  key={link}
                  href="#"
                  className="flex items-center gap-1 rounded-full px-3.5 py-1.5 text-sm text-white/80 transition hover:bg-white/10 hover:text-white"
                >
                  {link}
                  {link === 'Contact' && <ArrowUpRight className="h-3.5 w-3.5" />}
                </a>
              ))}
            </motion.div>

            <button
              className="rounded-full border border-gray-700 p-2 text-white/80 transition hover:text-white lg:hidden"
              onClick={() => setMenuOpen((v) => !v)}
              aria-label="Toggle menu"
            >
              {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>
          </nav>

          {/* Mobile menu */}
          {menuOpen && (
            <motion.div
              className="mt-3 flex flex-col gap-1 rounded-2xl border border-gray-700 bg-black/70 p-3 backdrop-blur lg:hidden"
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
            >
              {NAV_LINKS.map((link) => (
                <a key={link} href="#" className="rounded-lg px-3 py-2 text-sm text-white/80 hover:bg-white/10 hover:text-white">
                  {link}
                </a>
              ))}
            </motion.div>
          )}
        </header>

        {/* Top two-column intro */}
        <div className="mx-auto w-full max-w-7xl px-5 pt-6 sm:px-8">
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            <motion.p
              className="max-w-md text-sm text-white/80 md:text-base"
              variants={fadeUp}
              initial="hidden"
              animate="show"
              custom={1}
            >
              We deliver safe, affordable and reliable bike & car rides and errands — empowering
              people across Kenya to move better, every single day.
            </motion.p>
            <motion.p
              className="text-sm font-medium text-white/80 md:text-base lg:text-right"
              variants={fadeUp}
              initial="hidden"
              animate="show"
              custom={1.4}
            >
              Your City. Your Ride. Your Earnings!
            </motion.p>
          </div>
        </div>

        {/* Hero centre */}
        <div className="flex flex-1 items-center">
          <div className="mx-auto w-full max-w-7xl px-5 sm:px-8">
            <div className="flex flex-col items-center text-center">
              <motion.p
                className="mb-5 text-xs uppercase tracking-tight text-white/80 md:text-sm"
                variants={fadeUp}
                initial="hidden"
                animate="show"
                custom={1.6}
              >
                Founding Riders Program — First 20 Register Free
              </motion.p>

              <motion.h1
                className="font-medium leading-[0.85] tracking-tighter"
                variants={fadeUp}
                initial="hidden"
                animate="show"
                custom={1.9}
              >
                <span className="block text-5xl text-white sm:text-7xl md:text-8xl xl:text-9xl">Move Better.</span>
                <span className="block text-5xl sm:text-7xl md:text-8xl xl:text-9xl">
                  <ShinyText text="Earn More." baseColor="#12A0D7" shineColor="#ffffff" speed={3} spread={100} />
                </span>
              </motion.h1>

              <motion.a
                href="#"
                className="group mt-9 inline-flex items-center gap-2 rounded-full border border-white/15 bg-black px-6 py-3 text-sm font-medium text-white transition hover:bg-gray-900 md:px-8 md:py-4 md:text-base"
                variants={fadeUp}
                initial="hidden"
                animate="show"
                custom={2.2}
              >
                Download the App
                <ArrowUpRight className="h-4 w-4 transition-transform duration-300 group-hover:translate-x-1 group-hover:-translate-y-0.5" />
              </motion.a>
            </div>
          </div>
        </div>

        {/* Footer strip */}
        <div className="mx-auto w-full max-w-7xl px-5 pb-6 sm:px-8">
          <div className="flex flex-col items-center justify-between gap-2 border-t border-white/10 pt-4 text-xs text-white/60 sm:flex-row">
            <span>© 2026 U-Bike. Move Better. Earn More.</span>
            <span>Secure payments by Paystack · Operating in Kenya</span>
          </div>
        </div>
      </div>
    </main>
  );
}
