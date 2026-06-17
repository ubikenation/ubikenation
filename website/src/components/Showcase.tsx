import { motion } from 'framer-motion';

interface Photo {
  src: string;
  label: string;
  tall?: boolean;
}

// Drop the 4 photos into website/public/img/ with these exact filenames.
const PHOTOS: Photo[] = [
  { src: '/img/ebike.jpg', label: 'Electric bikes', tall: true },
  { src: '/img/fleet.jpg', label: 'A fleet for every trip' },
  { src: '/img/hail.jpg', label: 'A ride in seconds' },
  { src: '/img/bikeshare.jpg', label: 'Move the smart way', tall: true },
];

/**
 * Scrolling photo showcase below the hero. Images live in /public/img.
 * Each tile has a brand gradient backdrop so it still looks intentional
 * before the photo loads.
 */
export default function Showcase() {
  return (
    <section className="relative w-full bg-black px-5 py-20 sm:px-8 sm:py-28">
      <div className="mx-auto max-w-7xl">
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
        >
          <p className="text-xs uppercase tracking-tight text-white/60">Real rides, real cities</p>
          <h2 className="mt-2 max-w-2xl text-3xl font-medium tracking-tight text-white sm:text-5xl">
            Built for how your city actually moves.
          </h2>
        </motion.div>

        <div className="mt-12 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
          {PHOTOS.map((photo, i) => (
            <motion.figure
              key={photo.src}
              className={`group relative overflow-hidden rounded-2xl bg-gradient-to-br from-brand/30 to-black ${
                photo.tall ? 'row-span-2 aspect-[3/5]' : 'aspect-square'
              }`}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-60px' }}
              transition={{ duration: 0.6, delay: i * 0.08, ease: [0.22, 1, 0.36, 1] }}
            >
              <img
                src={photo.src}
                alt={photo.label}
                loading="lazy"
                className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent" />
              <figcaption className="absolute bottom-3 left-4 text-sm font-medium text-white drop-shadow">
                {photo.label}
              </figcaption>
            </motion.figure>
          ))}
        </div>
      </div>
    </section>
  );
}
