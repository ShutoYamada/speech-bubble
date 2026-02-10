import React, { useRef } from 'react';

interface VideoUploaderProps {
  onVideoSelect: (file: File) => void;
}

export const VideoUploader: React.FC<VideoUploaderProps> = ({ onVideoSelect }) => {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      onVideoSelect(file);
    }
  };

  const handleLoadClick = () => {
    fileInputRef.current?.click();
  };

  return (
    <div className="video-uploader">
      <button className="button secondary" disabled>
        動画撮影 (Mock)
      </button>
      <button className="button primary" onClick={handleLoadClick}>
        動画読み込み
      </button>
      <input
        type="file"
        accept="video/*"
        ref={fileInputRef}
        onChange={handleFileChange}
        style={{ display: 'none' }}
      />
    </div>
  );
};
