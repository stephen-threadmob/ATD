import type { Config } from 'tailwindcss';

/**
 * ATD design tokens. Athletic, high-contrast, franchise-ready.
 * Colours are exposed as CSS variables so a future location or franchisee can
 * be rebranded from the database (organizations.branding) without a rebuild.
 */
const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy:   { 50:'#f2f5f9',100:'#e3eaf3',200:'#c2d1e5',300:'#8fa9cc',400:'#587cad',
                  500:'#365d92',600:'#264878',700:'#1c3760',800:'#132849',900:'#0B2545',950:'#06172c' },
        clay:   { 50:'#fdf3f4',100:'#fbe5e7',200:'#f7ced3',300:'#f0a6b0',400:'#e57387',
                  500:'#d64860',600:'#C8102E',700:'#a30c26',800:'#880e24',900:'#751023',90:'#40040e' },
        chalk:  { 50:'#ffffff',100:'#F5F6F8',200:'#e9ebef',300:'#d6dae1',400:'#b0b7c3',
                  500:'#8b94a3',600:'#6b7484',700:'#545b69',800:'#3c414c',900:'#22262e' },
        turf:   { 500:'#1a7f37', 600:'#146c2e' },
        warn:   { 500:'#bf8700', 600:'#9a6d00' },
      },
      fontFamily: {
        display: ['var(--font-display)', 'Barlow Condensed', 'system-ui', 'sans-serif'],
        sans: ['var(--font-body)', 'Inter', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'monospace'],
      },
      borderRadius: { xl: '0.875rem', '2xl': '1.125rem' },
      boxShadow: {
        card: '0 1px 2px rgba(11,37,69,.06), 0 4px 16px rgba(11,37,69,.06)',
        lift: '0 8px 30px rgba(11,37,69,.12)',
      },
      keyframes: {
        'slide-up': { from: { opacity:'0', transform:'translateY(6px)' }, to: { opacity:'1', transform:'none' } },
        pulseSoft: { '0%,100%': { opacity:'1' }, '50%': { opacity:'.55' } },
      },
      animation: {
        'slide-up': 'slide-up .18s ease-out',
        'pulse-soft': 'pulseSoft 2s ease-in-out infinite',
      },
    },
  },
  plugins: [],
};
export default config;
