import type { CSSProperties, HTMLAttributes, ReactNode } from "react";

export type PlayerCardFacetView = {
  key: string;
  label: string;
  value: number | string;
};

type PlayerCardViewProps = {
  ariaLabel?: string;
  className?: string;
  facets: PlayerCardFacetView[];
  featuredBadge?: ReactNode;
  meta: string;
  name: string;
  photoAction?: ReactNode;
  photoAlt?: string;
  photoClassName?: string;
  photoProps?: Omit<HTMLAttributes<HTMLSpanElement>, "className" | "children">;
  photoSrc?: string | null;
  photoStyle?: CSSProperties;
  position: string;
  score: number | string;
  title?: ReactNode;
  trend?: ReactNode;
};

export function PlayerCardView({
  ariaLabel,
  className = "",
  facets,
  featuredBadge,
  meta,
  name,
  photoAction,
  photoAlt,
  photoClassName = "",
  photoProps,
  photoSrc,
  photoStyle,
  position,
  score,
  title,
  trend,
}: PlayerCardViewProps) {
  const nameClassName = name.length > 15 ? "fifa-player-name-long" : undefined;

  return (
    <div aria-label={ariaLabel} className={`fifa-player-card ${className}`.trim()}>
      <span className="fifa-score">{score}</span>
      {trend}
      <span className="fifa-position">{position}</span>
      <span {...photoProps} className={`fifa-photo ${photoClassName}`.trim()}>
        {photoSrc ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photoSrc} alt={photoAlt ?? ""} draggable={false} style={photoStyle} />
        ) : (
          <b>+</b>
        )}
      </span>
      {featuredBadge}
      <strong className={nameClassName}>{name}</strong>
      {title}
      <span className="fifa-card-meta">{meta}</span>
      <div className="fifa-facets">
        {facets.map((facet) => (
          <span key={facet.key}>
            <b>{facet.value}</b>
            {facet.label}
          </span>
        ))}
      </div>
      {photoAction}
    </div>
  );
}
