import { useEffect, useRef, useState } from 'react';
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

  const processVideo = () => {
    if (videoRef.current && isModelLoaded) {
      const video = videoRef.current;
      if (video.paused || video.ended || video.readyState < 2) return;
      if (video.videoWidth === 0 || video.videoHeight === 0) return;

      // Use video.currentTime * 1000 for the timestamp to sync with the video frame
      const startTimeMs = video.currentTime * 1000;
      const results = detectFaceLandmarks(video, startTimeMs);

      console.log("results", results);

      if (results && results.faceLandmarks && results.faceLandmarks.length > 0) {
        const landmarks = results.faceLandmarks[0];
        if (isMouthOpen(landmarks)) {
           const mouthPos = getMouthPosition(landmarks);
           if(mouthPos && videoRef.current) {
               // Calculate the actual displayed size of the video
               const rect = videoRef.current.getBoundingClientRect();
               
               // The video element takes up usage space (rect), but the actual video content might be letterboxed/pillarboxed inside it if object-fit: contain is used (default behaviour of video tag usually).
               // However, without object-fit specified in CSS, 'video' usually behaves like 'contain' or stretches? 
               // Actually, HTMLVideoElement default object-fit is 'contain'.
               // To keep it simple, let's assume the video fills the rect or we do the math. 
               // For now, let's stick to simple mapping and ensure CSS makes video fill the width/height or use object-fit: cover if we want exact filling, 
               // OR more robustly, calculate the scale.
               
               // Let's assume the CSS width/height matches the rendered video for now.
               // If there are black bars, this mapping will be slightly off, but should still be close enough for verification.
               
               // Better approach:
               // The landmarks are normalized (0.0 - 1.0) relative to the *video frame*.
               // If the video is displayed with 'object-fit: contain' (default), we need to know the drawn dimensions.
               
               // Let's rely on the simple rect mapping first, as it's the most likely issue being empty results, not positioning yet.
               // But we need to make sure we are not calculating garbage if landmarks happen to appear.
               
               setBubblePosition({
                   x: rect.left + mouthPos.x * rect.width,
                   y: rect.top + mouthPos.y * rect.height
               });
           }
        } else {
            setBubblePosition(null);
        }
      }

      requestRef.current = requestAnimationFrame(processVideo);
    }
  };

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
  }, [videoSrc, isModelLoaded]); // Re-bind when videoSrc changes mainly


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
