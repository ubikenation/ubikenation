import type { CSSProperties } from 'react';

interface ShinyTextProps {
  text: string;
  /** Base text colour (visible body of the letters). */
  baseColor?: string;
  /** Colour of the moving highlight. */
  shineColor?: string;
  /** Seconds per sweep. */
  speed?: number;
  /** Gradient angle in degrees. */
  spread?: number;
  className?: string;
}

/**
 * Animated shiny gradient text. A highlight band sweeps continuously across the
 * letters (clipped to the text), looping seamlessly. Honours reduced-motion.
 */
export default function ShinyText({
  text,
  baseColor = '#12A0D7',
  shineColor = '#ffffff',
  speed = 3,
  spread = 100,
  className = '',
}: ShinyTextProps) {
  const style = {
    '--base': baseColor,
    '--shine': shineColor,
    '--speed': `${speed}s`,
    '--spread': `${spread}deg`,
  } as CSSProperties;

  return (
    <span className={`shiny-text ${className}`} style={style}>
      {text}
    </span>
  );
}
