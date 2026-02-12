import {
  FaceLandmarker,
  FilesetResolver,
} from '@mediapipe/tasks-vision';

let faceLandmarker: FaceLandmarker | undefined;

const THRESHOLD = 0.02;

export const initializeFaceLandmarker = async () => {
  const filesetResolver = await FilesetResolver.forVisionTasks(
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.3/wasm'
  );
  faceLandmarker = await FaceLandmarker.createFromOptions(filesetResolver, {
    baseOptions: {
      modelAssetPath: `https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task`,
      delegate: 'GPU',
    },
    outputFaceBlendshapes: true,
    runningMode: 'VIDEO',
    numFaces: 1,
    minFaceDetectionConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });
  return faceLandmarker;
};

export const detectFaceLandmarks = (video: HTMLVideoElement, timestamp: number) => {
  if (!faceLandmarker) return null;
  return faceLandmarker.detectForVideo(video, timestamp);
};

// Calculate mouth openness based on upper and lower lip landmarks
// Using key landmarks for lips (referencing MediaPipe mash)
// Upper lip bottom: 13
// Lower lip top: 14
export const isMouthOpen = (landmarks: any[]) => {
  if (!landmarks || landmarks.length === 0) return false;

  const upperLipBottom = landmarks[13];
  const lowerLipTop = landmarks[14];

  if (!upperLipBottom || !lowerLipTop) return false;

  const distance = Math.abs(upperLipBottom.y - lowerLipTop.y);
  
  // Threshold can be adjusted. Normalized coordinates.
  return distance > THRESHOLD; 
};

export const getMouthPosition = (landmarks: any[]) => {
    if (!landmarks || landmarks.length === 0) return null;
    // return position of landmark 13 (upper lip)
    return landmarks[13];
}
