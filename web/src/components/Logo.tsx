type LogoProps = {
  className?: string;
};

export function Logo({ className }: LogoProps) {
  return (
    <svg
      width="30"
      height="13"
      viewBox="0 0 30 13"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <path d="M2.5 3.1 9.5 3.1 8 10.9 1 10.9 2.5 3.1Z" fill="#F0618C" />
      <path d="M10.5 3.1 17.5 3.1 16 10.9 9 10.9 10.5 3.1Z" fill="#3EC6EA" />
    </svg>
  );
}