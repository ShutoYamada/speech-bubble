import React from 'react';

interface SpeechBubbleOverlayProps {
  position: { x: number; y: number } | null;
  text: string;
}

export const SpeechBubbleOverlay: React.FC<SpeechBubbleOverlayProps> = ({ position, text }) => {
  if (!position) return null;

  return (
    <div
      className="speech-bubble"
      style={{
        left: position.x,
        top: position.y,
      }}
    >
      {text}
    </div>
  );
};
