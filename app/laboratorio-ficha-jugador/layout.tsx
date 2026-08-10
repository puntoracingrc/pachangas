import type { Metadata } from "next";
import styles from "./layout.module.css";

export const metadata: Metadata = {
  title: "Laboratorio de ficha de jugador · Pachangas IQ",
  robots: { follow: false, index: false },
};

export default function PlayerCardLabLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <>
      <span className={styles.labBadge}>Laboratorio</span>
      {children}
    </>
  );
}
