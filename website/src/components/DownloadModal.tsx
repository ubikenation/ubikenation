import { motion, AnimatePresence } from 'framer-motion';
import { X, Bike, Car, ShoppingBag, User, Download } from 'lucide-react';

const REPO = 'https://github.com/ubikenation/ubikenation/releases/latest/download';

interface AppDownload {
  name: string;
  desc: string;
  file: string;
  icon: typeof User;
  accent: string;
}

const APPS: AppDownload[] = [
  { name: 'Passenger App', desc: 'Book bikes, cars & errands', file: 'ubike-customer.apk', icon: User, accent: 'text-brand' },
  { name: 'Bike Rider App', desc: 'Earn on a bike', file: 'ubike-bike-rider.apk', icon: Bike, accent: 'text-leaf' },
  { name: 'Car Rider App', desc: 'Earn with your car', file: 'ubike-car-rider.apk', icon: Car, accent: 'text-brand' },
  { name: 'Errands Rider App', desc: 'Earn running errands', file: 'ubike-errands-rider.apk', icon: ShoppingBag, accent: 'text-leaf' },
];

export default function DownloadModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <motion.div
            className="relative w-full max-w-lg rounded-3xl bg-white p-6 sm:p-8"
            initial={{ opacity: 0, scale: 0.95, y: 16 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 16 }}
            transition={{ duration: 0.25 }}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={onClose}
              className="absolute right-4 top-4 rounded-full p-1.5 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
              aria-label="Close"
            >
              <X className="h-5 w-5" />
            </button>

            <div className="flex items-center gap-3">
              <img src="/logo.png" alt="U-Bike" className="h-9 w-auto" />
            </div>
            <h3 className="mt-4 text-xl font-bold text-slate-900">Choose your app</h3>
            <p className="mt-1 text-sm text-slate-500">Download the Android app that fits you (APK).</p>

            <div className="mt-6 space-y-3">
              {APPS.map((app) => (
                <a
                  key={app.file}
                  href={`${REPO}/${app.file}`}
                  className="group flex items-center gap-4 rounded-2xl border border-slate-200 p-4 transition hover:border-brand hover:bg-slate-50"
                >
                  <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-slate-100">
                    <app.icon className={`h-6 w-6 ${app.accent}`} />
                  </span>
                  <span className="flex-1">
                    <span className="block font-semibold text-slate-900">{app.name}</span>
                    <span className="block text-xs text-slate-500">{app.desc}</span>
                  </span>
                  <Download className="h-5 w-5 text-slate-400 transition group-hover:text-brand" />
                </a>
              ))}
            </div>

            <p className="mt-5 text-center text-xs text-slate-400">
              On Android, enable “Install from unknown sources” to install the APK.
            </p>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
