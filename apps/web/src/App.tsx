import { useEffect, useRef, useState, useCallback } from 'react';
import './App.css';
import { Header } from './components/Header';
import { VideoUploader } from './components/VideoUploader';
import { SpeechBubbleOverlay } from './components/SpeechBubbleOverlay';
import {
  initializeFaceLandmarker,
  detectFaceLandmarks,
  isMouthOpen,
  getMouthPosition
} from './utils/mediaPipeUtils';

function App() {
  const [videoSrc, setVideoSrc] = useState<string | null>(null);
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [bubblePosition, setBubblePosition] = useState<{ x: number; y: number } | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const requestRef = useRef<number | undefined>(undefined);

  useEffect(() => {
    const loadModel = async () => {
      await initializeFaceLandmarker();
      setIsModelLoaded(true);
      console.log('Model loaded');
    };
    loadModel();
  }, []);

  const handleVideoSelect = (file: File) => {
    const url = URL.createObjectURL(file);
    setVideoSrc(url);
    // Reset bubble position when new video is loaded
    setBubblePosition(null);
  };

  const processVideo = useCallback(function loop() {
    if (videoRef.current && isModelLoaded) {
      const video = videoRef.current;
      if (video.paused || video.ended || video.readyState < 2) return;
      if (video.videoWidth === 0 || video.videoHeight === 0) return;

      // Use video.currentTime * 1000 for the timestamp to sync with the video frame
      const startTimeMs = video.currentTime * 1000;
      const results = detectFaceLandmarks(video, startTimeMs);

      if (results && results.faceLandmarks && results.faceLandmarks.length > 0) {
        const landmarks = results.faceLandmarks[0];
        const isOpen = isMouthOpen(landmarks);
        const mouthPos = getMouthPosition(landmarks);

        if (isOpen) {
           if(mouthPos && videoRef.current) {
               // Calculate the actual displayed size of the video
               const rect = videoRef.current.getBoundingClientRect();
               
               // SpeechBubbleOverlayは.video-container内でposition: absoluteで配置されているため、
               // 親要素を基準とした相対座標を使用する必要がある
               // rect.left/topはビューポート座標なので加算しない
               const x = mouthPos.x * rect.width;
               const y = mouthPos.y * rect.height;

               setBubblePosition({
                   x: x, 
                   y: y
               });
           }
        } else {
            setBubblePosition(null);
        }
      }

      requestRef.current = requestAnimationFrame(loop);
    }
  }, [isModelLoaded]);

  useEffect(() => {
      // Start processing when video plays
      const video = videoRef.current;
      if(!video) return;

      const onPlay = () => {
          requestRef.current = requestAnimationFrame(processVideo);
      }

      const onPause = () => {
          if(requestRef.current) cancelAnimationFrame(requestRef.current);
      }

      video.addEventListener('play', onPlay);
      video.addEventListener('pause', onPause);

      return () => {
        video.removeEventListener('play', onPlay);
        video.removeEventListener('pause', onPause);
        if(requestRef.current) cancelAnimationFrame(requestRef.current);
      }
  }, [videoSrc, processVideo]); // Re-bind when videoSrc or processVideo changes


  return (
    <div className="app-container">
      <Header />
      <main className="main-content">
        {!videoSrc && (
          <div className="upload-section">
             {!isModelLoaded && <p>Loading Model...</p>}
             <VideoUploader onVideoSelect={handleVideoSelect} />
          </div>
        )}
        
        {videoSrc && (
          <div className="video-container">
            <video
              ref={videoRef}
              src={videoSrc}
              controls
              autoPlay
              className="main-video"
              crossOrigin="anonymous" 
            />
            <SpeechBubbleOverlay position={bubblePosition} text="Mock Text..." />
             <div className="controls">
                <button onClick={() => setVideoSrc(null)}>Re-upload</button>
             </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default App;
