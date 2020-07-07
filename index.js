import {
  Scene,
  WebGLRenderer,
  PerspectiveCamera,
  Mesh,
  BufferGeometry,
  BufferAttribute,
  ShaderMaterial,
  TextureLoader,
  FrontSide,
  AmbientLight,
  DirectionalLight,
  ShaderLib,
  UniformsUtils,
  UniformsLib,
  NearestFilter
} from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls";
import { getPixels, decodeDEM, maxHeight } from "./utils";
import Martini from "@mapbox/martini";
import pomVert from "./shaders/pom.vertex.glsl";
import pomFrag from "./shaders/pom.fragment.glsl";

const scene = new Scene();
const camera = new PerspectiveCamera(
  90,
  window.innerWidth / window.innerHeight,
  0.1,
  1000
);
const renderer = new WebGLRenderer();
const canvas = renderer.domElement;
const controls = new OrbitControls(camera, canvas);
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(canvas);

const metersPerPixel = 124.73948277849482;
const terrainScale = 0.01;
const terrainExaggeration = 2;
camera.position.set(
  metersPerPixel * terrainScale,
  metersPerPixel * terrainScale,
  400
);
camera.lookAt(0, 0, 0);

new TextureLoader().load(
  "https://api.mapbox.com/v4/mapbox.terrain-rgb/10/906/404.png?access_token=pk.eyJ1IjoiYXJpbmRhbTE5OTMiLCJhIjoiY2p0bnU2dmtoMHp4ZTN5cGxmZXJpa3BpdiJ9._9GLi1K1ERIMzwpzWSL-PA",
  texture => {
    const pixels = getPixels(texture);
    const decodedDem = decodeDEM(pixels);
    const max = Math.max(...decodedDem);
    const martini = new Martini(257);
    // generate RTIN hierarchy from terrain data (an array of size^2 length)
    const tile = martini.createTile(decodedDem);

    // get a mesh (vertices and triangles indices) for a 50m error
    const martiniMesh = tile.getMesh(50);
    const numVertices = martiniMesh.vertices.length / 2;
    const numTriangles = martiniMesh.triangles.length / 3;
    const vertices = new Float32Array(numVertices * 3);
    const uv = new Float32Array(numVertices * 2);
    // build up vertex and uv buffer
    for (let i = 0; i < numVertices; i++) {
      const x = martiniMesh.vertices[2 * i];
      const y = martiniMesh.vertices[2 * i + 1];
      const z = decodedDem[y * 257 + x];

      vertices[3 * i] = x * metersPerPixel * terrainScale;
      vertices[3 * i + 1] = y * metersPerPixel * terrainScale;
      vertices[3 * i + 2] = max * terrainScale;

      uv[2 * i] = x / 257;
      uv[2 * i + 1] = 1 - y / 257;
    }
    // switch triangles to be winding order consisten with threejs expectation
    for (let i = 0; i < numTriangles; i++) {
      const temp = martiniMesh.triangles[3 * i + 1];
      martiniMesh.triangles[3 * i + 1] = martiniMesh.triangles[3 * i + 2];
      martiniMesh.triangles[3 * i + 2] = temp;
    }

    const geometry = new BufferGeometry();
    geometry.setAttribute("position", new BufferAttribute(vertices, 3));
    geometry.setAttribute("uv", new BufferAttribute(uv, 2));
    geometry.setIndex(new BufferAttribute(martiniMesh.triangles, 1));
    geometry.computeBoundingBox();
    geometry.computeVertexNormals();

    let uniforms = UniformsUtils.clone(ShaderLib.standard.uniforms);
    uniforms["heightmap"] = { value: texture };
    uniforms["maxHeight"] = { value: max * terrainScale };
    uniforms["terrainScale"] = { value: terrainScale };
    // uniforms["exaggeration"] = { value: terrainExaggeration };
    // console.log(max * terrainScale * terrainExaggeration);

    const material = new ShaderMaterial({
      uniforms,
      lights: true,
      vertexShader: pomVert,
      fragmentShader: pomFrag
    });
    const mesh = new Mesh(geometry, material);
    scene.add(mesh);

    // Add lights
    const ambient = new AmbientLight(0x404040); // soft white
    scene.add(ambient);
    const directional = new DirectionalLight(0x404040, 3);
    directional.position.set(1, 1, 1);
    scene.add(directional);

    window.onresize = () => {
      renderer.setSize(window.innerWidth, window.innerHeight);
    };

    const onRenderFrame = () => {
      controls.update();
      renderer.render(scene, camera);
      window.requestAnimationFrame(onRenderFrame);
    };

    window.requestAnimationFrame(onRenderFrame);
  }
);
