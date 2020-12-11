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
  NearestFilter,
  MeshBasicMaterial,
  Vector3,
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

const metersPerPixel = 124.73948277849482 / 4;
const terrainScale = 0.01;
const metersPerTile = metersPerPixel * 512 * terrainScale;
const terrainExaggeration = 3;
camera.position.set(
  metersPerPixel * terrainScale,
  metersPerPixel * terrainScale,
  400
);
camera.lookAt(0, 0, 0);
const allUniforms = [];

function addTile(z, x, y, offsetX, offsetY) {
  const demPromise = new Promise((resolve, reject) => {
    new TextureLoader().load(
      `https://api.mapbox.com/v4/mapbox.terrain-rgb/${z}/${x}/${y}@2x.png?access_token=pk.eyJ1IjoiYXJpbmRhbTE5OTMiLCJhIjoiY2p0bnU2dmtoMHp4ZTN5cGxmZXJpa3BpdiJ9._9GLi1K1ERIMzwpzWSL-PA`,
      (texture) => {
        resolve(texture);
      }
    );
  });

  const rasterPromise = new Promise((resolve, reject) => {
    new TextureLoader().load(
      `https://api.mapbox.com/v4/mapbox.satellite/${z}/${x}/${y}@2x.png?access_token=pk.eyJ1IjoiYXJpbmRhbTE5OTMiLCJhIjoiY2p0bnU2dmtoMHp4ZTN5cGxmZXJpa3BpdiJ9._9GLi1K1ERIMzwpzWSL-PA`,
      (texture) => {
        resolve(texture);
      }
    );
  });

  Promise.all([demPromise, rasterPromise]).then(([texture, rasterTexture]) => {
    const pixels = getPixels(texture);
    const decodedDem = decodeDEM(pixels);
    let max = -1;
    for (let i = 0; i < decodedDem.length; i++) {
      if (decodedDem[i] > max) {
        max = decodedDem[i];
      }
    }

    const martini = new Martini(513);
    // generate RTIN hierarchy from terrain data (an array of size^2 length)
    const tile = martini.createTile(decodedDem);

    // get a mesh (vertices and triangles indices) for a 50m error
    const martiniMesh = tile.getMesh(100);
    // const numVertices = martiniMesh.vertices.length / 2;
    const numTriangles = martiniMesh.triangles.length / 3;
    // build up vertex and uv buffer
    // for (let i = 0; i < numVertices; i++) {
    //   const x = martiniMesh.vertices[2 * i];
    //   const y = martiniMesh.vertices[2 * i + 1];
    //   const z = decodedDem[y * 513 + x];

    //   vertices[3 * i] = x * metersPerPixel * terrainScale;
    //   vertices[3 * i + 1] = y * metersPerPixel * terrainScale;
    //   vertices[3 * i + 2] = z * terrainScale * terrainExaggeration + 10;

    //   uv[2 * i] = x / 513;
    //   uv[2 * i + 1] = 1 - y / 513;
    // }

    //duplicate vertices so that we can have flat triangles
    const vertices = new Float32Array(numTriangles * 3 * 3);
    const planeVertices = new Float32Array(numTriangles * 3 * 3);
    const indices = new Uint16Array(numTriangles * 3);

    let vertCtr = 0;
    const pushTriangle = (i) => {
      // debugger;
      const v1 = martiniMesh.triangles[3 * i];
      const v2 = martiniMesh.triangles[3 * i + 1];
      const v3 = martiniMesh.triangles[3 * i + 2];

      const v1x = martiniMesh.vertices[2 * v1];
      const v1y = martiniMesh.vertices[2 * v1 + 1];
      const v1z = decodedDem[v1y * 513 + v1x];

      const v2x = martiniMesh.vertices[2 * v2];
      const v2y = martiniMesh.vertices[2 * v2 + 1];
      const v2z = decodedDem[v2y * 513 + v2x];

      const v3x = martiniMesh.vertices[2 * v3];
      const v3y = martiniMesh.vertices[2 * v3 + 1];
      const v3z = decodedDem[v3y * 513 + v3x];

      const v1xf =
        v1x * metersPerPixel * terrainScale + offsetX * metersPerTile;
      const v1yf =
        v1y * metersPerPixel * terrainScale + offsetY * metersPerTile;
      const v1zf = v1z * terrainScale * terrainExaggeration + 4;

      const v2xf =
        v2x * metersPerPixel * terrainScale + offsetX * metersPerTile;
      const v2yf =
        v2y * metersPerPixel * terrainScale + offsetY * metersPerTile;
      const v2zf = v2z * terrainScale * terrainExaggeration + 4;

      const v3xf =
        v3x * metersPerPixel * terrainScale + offsetX * metersPerTile;
      const v3yf =
        v3y * metersPerPixel * terrainScale + offsetY * metersPerTile;
      const v3zf = v3z * terrainScale * terrainExaggeration + 4;

      const cxf = (v1xf + v2xf + v3xf) / 3;
      const cyf = (v1yf + v2yf + v3yf) / 3;
      const czf = (v1zf + v2zf + v3zf) / 3;

      // Add each vertex
      vertices[3 * vertCtr] = v1xf;
      vertices[3 * vertCtr + 1] = v1yf;
      vertices[3 * vertCtr + 2] = v1zf;
      planeVertices[3 * vertCtr] = cxf;
      planeVertices[3 * vertCtr + 1] = cyf;
      planeVertices[3 * vertCtr + 2] = czf;
      indices[3 * i] = vertCtr;
      vertCtr++;

      vertices[3 * vertCtr] = v3xf;
      vertices[3 * vertCtr + 1] = v3yf;
      vertices[3 * vertCtr + 2] = v3zf;
      planeVertices[3 * vertCtr] = cxf;
      planeVertices[3 * vertCtr + 1] = cyf;
      planeVertices[3 * vertCtr + 2] = czf;
      indices[3 * i + 1] = vertCtr;
      vertCtr++;

      vertices[3 * vertCtr] = v2xf;
      vertices[3 * vertCtr + 1] = v2yf;
      vertices[3 * vertCtr + 2] = v2zf;
      planeVertices[3 * vertCtr] = cxf;
      planeVertices[3 * vertCtr + 1] = cyf;
      planeVertices[3 * vertCtr + 2] = czf;
      indices[3 * i + 2] = vertCtr;
      vertCtr++;
    };

    for (let i = 0; i < numTriangles; i++) {
      pushTriangle(i);
    }

    const geometry = new BufferGeometry();
    geometry.setAttribute("position", new BufferAttribute(vertices, 3));
    geometry.setAttribute(
      "planePosition",
      new BufferAttribute(planeVertices, 3)
    );
    geometry.setIndex(new BufferAttribute(indices, 1));
    geometry.computeBoundingBox();
    geometry.computeVertexNormals();

    let uniforms = UniformsUtils.clone(ShaderLib.standard.uniforms);
    uniforms["heightmap"] = { value: texture };
    uniforms["maxHeight"] = { value: max * terrainScale * terrainExaggeration };
    uniforms["map"] = { value: rasterTexture };
    uniforms["terrainScale"] = { value: terrainScale };
    uniforms["exaggeration"] = { value: terrainExaggeration };
    uniforms["cPos"] = { value: camera.getWorldPosition() };
    uniforms["meshOrigin"] = {
      value: new Vector3(offsetX * metersPerTile, offsetY * metersPerTile, 0),
    };

    allUniforms.push(uniforms);

    const material = new ShaderMaterial({
      uniforms,
      lights: true,
      vertexShader: pomVert,
      fragmentShader: pomFrag,
    });
    const mesh = new Mesh(geometry, material);
    const wireframe = new Mesh(
      geometry,
      new MeshBasicMaterial({ wireframe: true })
    );
    // wireframe.position.set(offsetX * metersPerTile, offsetY * metersPerTile, 0);

    scene.add(mesh);
    scene.add(wireframe);
  });
}

addTile(14, 2747, 6335, 0, 0);
addTile(14, 2746, 6335, -1, 0);
addTile(14, 2747, 6336, 0, 1);
addTile(14, 2746, 6336, -1, 1);

// Add lights
const ambient = new AmbientLight(0x404040, 3); // soft white
scene.add(ambient);
const directional = new DirectionalLight(0x404040, 0.0001);
directional.position.set(1, 1, 1);
scene.add(directional);

window.onresize = () => {
  renderer.setSize(window.innerWidth, window.innerHeight);
};

const onRenderFrame = () => {
  controls.update();
  camera.updateMatrixWorld();
  for (const uniforms of allUniforms) {
    uniforms["cPos"] = { value: camera.getWorldPosition() };
  }

  renderer.render(scene, camera);
  window.requestAnimationFrame(onRenderFrame);
};

window.requestAnimationFrame(onRenderFrame);
