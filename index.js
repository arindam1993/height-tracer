import {
  Scene,
  WebGLRenderer,
  PerspectiveCamera,
  Mesh,
  PlaneBufferGeometry,
  MeshBasicMaterial,
  DoubleSide
} from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls";

const scene = new Scene();
const camera = new PerspectiveCamera(
  90,
  window.innerWidth / window.innerHeight,
  0.1,
  1000
);
const renderer = new WebGLRenderer();
const controls = new OrbitControls(camera, renderer.domElement);
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

camera.position.set(0, 0, 5);
camera.lookAt(0, 0, 0);

const geometry = new PlaneBufferGeometry();
const material = new MeshBasicMaterial({
  color: 0xffff00,
  side: DoubleSide
});
const plane = new Mesh(geometry, material);
scene.add(plane);

window.onresize = () => {
  renderer.setSize(window.innerWidth, window.innerHeight);
};

const onRenderFrame = () => {
  controls.update();
  renderer.render(scene, camera);
  window.requestAnimationFrame(onRenderFrame);
};

window.requestAnimationFrame(onRenderFrame);
