precision highp float;

uniform vec2 resolution;

uniform mat4 viewMatrix;
uniform vec3 cameraPosition;

uniform mat4 cameraWorldMatrix;
uniform mat4 cameraProjectionMatrixInverse;

uniform sampler2D heightmap;

uniform float maxHeight;

vec2 rayPlaneIntersect(vec3 origin, vec3 dir, vec3 P, vec3 N, float height) {
  vec3 p = vec3(P.x, P.y, height);
  vec3 n = N;
  float l = dot(dir, n);
  float t = dot(p - origin, n)/l;
  
  vec3 pt = origin + dir*t;
  return vec2(pt.x + 0.5, pt.y + 0.5);
}

float getHeight(vec2 pt) {
  return  -10000.0 + (pt.x * 255.0 * 256.0 * 256.0 + pt.y * 255.0 * 256.0 + pt.z * 255.0) * 0.1;
}

float raymarch(vec3 origin, vec3 dir) {
  

}

void main(void) {
  // screen position
  vec2 screenPos = ( gl_FragCoord.xy * 2.0 - resolution ) / resolution;

  // ray direction in normalized device coordinate
  vec4 ndcRay = vec4( screenPos.xy, 1.0, 1.0 );

  // convert ray direction from normalized device coordinate to world coordinate
  vec3 ray = ( cameraWorldMatrix * cameraProjectionMatrixInverse * ndcRay ).xyz;
  ray = normalize( ray );

  // camera position
  vec3 cPos = cameraPosition;


  float height = -1.0;
  for(int i = NUM_STEPS - 1; i >= 1; i--){
    float upperHeight = maxHeight * float(i)/float(NUM_STEPS);
    float lowerHeight = maxHeight * float(i - 1)/float(NUM_STEPS);
    vec2 ptUpper = intersectTile(cPos, ray, upperHeight);
    vec2 ptlower = intersectTile(cPos, ray, lowerHeight);
   
   

  }

  vec2 uv = clamp(pt, 0.0, 1.0);
  vec3 split = texture2D(heightmap, uv).rgb;
  float height = -10000.0 + (split.x * 255.0 * 256.0 * 256.0 + split.y * 255.0 * 256.0 + split.z * 255.0) * 0.1;

  gl_FragColor = vec4(height/maxHeight, height/maxHeight, height/maxHeight, 1.0);
}