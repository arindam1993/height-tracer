precision highp float;
#define STANDARD
#define USE_UV
#define USE_MAP
#define MARCH_STEPS 200
#define TERRAIN_SCALE vec2(513.0 * 1.24739482778494/4.0, 513.0 * 1.24739482778494/4.0)

#ifdef PHYSICAL
	#define REFLECTIVITY
	#define CLEARCOAT
	#define TRANSPARENCY
#endif
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float roughness;
uniform float metalness;
uniform float opacity;

varying vec3 vWorldPosition;
varying vec3 vPlaneWorldPosition;
varying vec3 vPlaneNormal;
uniform vec3 cPos;
uniform vec3 meshOrigin;
uniform float maxHeight;
uniform float terrainScale;
uniform float exaggeration;
uniform sampler2D heightmap;
#ifdef TRANSPARENCY
	uniform float transparency;
#endif
#ifdef REFLECTIVITY
	uniform float reflectivity;
#endif
#ifdef CLEARCOAT
	uniform float clearcoat;
	uniform float clearcoatRoughness;
#endif
#ifdef USE_SHEEN
	uniform vec3 sheen;
#endif
varying vec3 vViewPosition;
#ifndef FLAT_SHADED
	varying vec3 vNormal;
	#ifdef USE_TANGENT
		varying vec3 vTangent;
		varying vec3 vBitangent;
	#endif
#endif
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <uv2_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <bsdfs>
#include <cube_uv_reflection_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_physical_pars_fragment>
#include <fog_pars_fragment>
#include <lights_pars_begin>
#include <lights_physical_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <clearcoat_pars_fragment>
#include <roughnessmap_pars_fragment>
#include <metalnessmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>

vec3 rayPlaneIntersect(vec3 origin, vec3 dir, vec3 P, vec3 N, float height) {
  vec3 p = P + height * vec3(0,0,1);
  float l = dot(dir, N);
  float t = dot(p - origin, N)/l;
  
  vec3 pt = origin + dir*t;
  return pt;
}

float sampleHeight(sampler2D heightmap, vec2 uv) {
  vec4 s = texture2D(heightmap, uv);
  return (-10000.0 + (s.x * 255.0 * 256.0 * 256.0 + s.y * 255.0 * 256.0 + s.z * 255.0) * 0.1) * terrainScale*exaggeration;
}

vec2 wsToUv(vec3 wsPos) {
  vec2 uv = (wsPos.xy - meshOrigin.xy)/TERRAIN_SCALE;
  uv.y = 1.0 - uv.y;
  return uv;
}

float raytrace(sampler2D heightmap, vec3 origin, vec3 dir, vec3 P, vec3 N, float height, out vec3 wsSamplePos) {
  vec3 wsInstersection = rayPlaneIntersect(origin, dir, P, N , height);
  wsSamplePos = wsInstersection;
  //scale by tilesize
  vec2 uv = wsToUv(wsInstersection);
  float h = sampleHeight(heightmap, uv);
  return h;
}

vec2 projectToBasis(vec3 pt, vec3 xbasis, vec3 ybasis){
  return vec2(dot(pt, xbasis), dot(pt,ybasis));
}

vec3 unprojectFromBasis(vec2 pt, vec3 xbasis, vec3 ybasis) {
  return xbasis*pt.x + ybasis*pt.y;
}

vec2 instersectLines(vec2 p1, vec2 p2, vec2 p3, vec2 p4) {
  float d = (p1.x - p2.x)*(p3.y - p4.y) - (p1.y - p2.y)*(p3.x - p4.x);
  return vec2(
    ((p1.x*p2.y - p1.y*p2.x)*(p3.x - p4.x) - (p1.x - p2.x)*(p3.x*p4.y - p3.y*p4.x))/d,
    ((p1.x*p2.y - p1.y*p2.x)*(p3.y - p4.y) - (p1.y - p2.y)*(p3.x*p4.y - p3.y*p4.x))/d
  );
}

vec3 interpolateBetweenMarches(vec3 prevSample, float prevHeight, vec3 currSample, float currHeight, vec3 normal, vec3 ray) {
  vec3 rayline = ray;
  vec3 ybasis = normal;
  vec3 xbasis = normalize(rayline - ybasis);

  vec2 r1 = projectToBasis(prevSample - currSample, xbasis, ybasis);
  vec2 r2 = projectToBasis(currSample - currSample, xbasis, ybasis);

  vec2 h1 = projectToBasis(vec3(prevSample.xy, prevHeight) - currSample, xbasis, ybasis);
  vec2 h2 = projectToBasis(vec3(currSample.xy, currHeight) - currSample, xbasis, ybasis);

  vec2 intersection = instersectLines(r1, r2, h1, h2);

  return currSample + unprojectFromBasis(intersection, xbasis, ybasis);
}

bool raymarch(sampler2D heightmap, vec3 origin, vec3 dir, vec3 worldPos, vec3 normal, out vec3 refinedWorldPos) {
  vec3 currWsPoint;
  float currHeight = raytrace(heightmap, origin, dir, worldPos, normal, 0.0, currWsPoint);

  vec3 prevWsPoint = vec3(currWsPoint);
  float prevHeight = currHeight;
  
  bool found = false;
  for( int i = 1; i < MARCH_STEPS; i++){
    float heightOffset = -10.0 * float(i)/float(MARCH_STEPS);
    currHeight = raytrace(heightmap, origin, dir, worldPos, normal, heightOffset, currWsPoint);

    //Ray has marched below terrain, we have found the hitpoint
    if(currHeight >= currWsPoint.z) {
      refinedWorldPos = interpolateBetweenMarches(prevWsPoint, prevHeight, currWsPoint, currHeight, normal, dir);
      found = true;
      break;
    }else{
      prevHeight = currHeight;
      prevWsPoint = vec3(currWsPoint);
    }
  }
  refinedWorldPos = currWsPoint;
  return found;
}


void main() {
  vec3 rayDir = normalize(vWorldPosition - cPos);
#if 0 > 0
	vec4 plane;
	
	#if 0 < 0
		bool clipped = true;
		
		if ( clipped ) discard;
	#endif
#endif
  vec3 refinedWorldPos;
  bool rayHit = raymarch(heightmap, cPos, rayDir, vPlaneWorldPosition, vPlaneNormal, refinedWorldPos);
  vec2 refinedUv = wsToUv(refinedWorldPos);
  if(!rayHit || refinedUv.x < 0.0 || refinedUv.x > 1.0 || refinedUv.y < 0.0 || refinedUv.y > 1.0 ){
    discard;
  }
	vec4 diffuseColor = vec4( diffuse, opacity );
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
#if defined( USE_LOGDEPTHBUF ) && defined( USE_LOGDEPTHBUF_EXT )
	gl_FragDepthEXT = vIsPerspective == 0.0 ? gl_FragCoord.z : log2( vFragDepth ) * logDepthBufFC * 0.5;
#endif
vec4 texelColor = texture2D( map, refinedUv );
// // texelColor = mapTexelToLinear( texelColor );
diffuseColor *= texelColor;
#ifdef USE_COLOR
	diffuseColor.rgb *= vColor;
#endif
#ifdef USE_ALPHAMAP
	diffuseColor.a *= texture2D( alphaMap, refinedUv ).g;
#endif
#ifdef ALPHATEST
	if ( diffuseColor.a < ALPHATEST ) discard;
#endif
float roughnessFactor = roughness;
#ifdef USE_ROUGHNESSMAP
	vec4 texelRoughness = texture2D( roughnessMap, refinedUv );
	roughnessFactor *= texelRoughness.g;
#endif
float metalnessFactor = metalness;
#ifdef USE_METALNESSMAP
	vec4 texelMetalness = texture2D( metalnessMap, refinedUv );
	metalnessFactor *= texelMetalness.b;
#endif
#ifdef FLAT_SHADED
	vec3 fdx = vec3( dFdx( vViewPosition.x ), dFdx( vViewPosition.y ), dFdx( vViewPosition.z ) );
	vec3 fdy = vec3( dFdy( vViewPosition.x ), dFdy( vViewPosition.y ), dFdy( vViewPosition.z ) );
	vec3 normal = normalize( cross( fdx, fdy ) );
#else
	vec3 normal = normalize( vNormal );
	#ifdef DOUBLE_SIDED
		normal = normal * ( float( gl_FrontFacing ) * 2.0 - 1.0 );
	#endif
	#ifdef USE_TANGENT
		vec3 tangent = normalize( vTangent );
		vec3 bitangent = normalize( vBitangent );
		#ifdef DOUBLE_SIDED
			tangent = tangent * ( float( gl_FrontFacing ) * 2.0 - 1.0 );
			bitangent = bitangent * ( float( gl_FrontFacing ) * 2.0 - 1.0 );
		#endif
		#if defined( TANGENTSPACE_NORMALMAP ) || defined( USE_CLEARCOAT_NORMALMAP )
			mat3 vTBN = mat3( tangent, bitangent, normal );
		#endif
	#endif
#endif
vec3 geometryNormal = normal;
#ifdef OBJECTSPACE_NORMALMAP
	normal = texture2D( normalMap, vUv ).xyz * 2.0 - 1.0;
	#ifdef FLIP_SIDED
		normal = - normal;
	#endif
	#ifdef DOUBLE_SIDED
		normal = normal * ( float( gl_FrontFacing ) * 2.0 - 1.0 );
	#endif
	normal = normalize( normalMatrix * normal );
#elif defined( TANGENTSPACE_NORMALMAP )
	vec3 mapN = texture2D( normalMap, vUv ).xyz * 2.0 - 1.0;
	mapN.xy *= normalScale;
	#ifdef USE_TANGENT
		normal = normalize( vTBN * mapN );
	#else
		normal = perturbNormal2Arb( -vViewPosition, normal, mapN );
	#endif
#elif defined( USE_BUMPMAP )
	normal = perturbNormalArb( -vViewPosition, normal, dHdxy_fwd() );
#endif
#ifdef CLEARCOAT
	vec3 clearcoatNormal = geometryNormal;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	vec3 clearcoatMapN = texture2D( clearcoatNormalMap, vUv ).xyz * 2.0 - 1.0;
	clearcoatMapN.xy *= clearcoatNormalScale;
	#ifdef USE_TANGENT
		clearcoatNormal = normalize( vTBN * clearcoatMapN );
	#else
		clearcoatNormal = perturbNormal2Arb( - vViewPosition, clearcoatNormal, clearcoatMapN );
	#endif
#endif
#ifdef USE_EMISSIVEMAP
	vec4 emissiveColor = texture2D( emissiveMap, vUv );
	emissiveColor.rgb = emissiveMapTexelToLinear( emissiveColor ).rgb;
	totalEmissiveRadiance *= emissiveColor.rgb;
#endif
	// accumulation
PhysicalMaterial material;
material.diffuseColor = diffuseColor.rgb * ( 1.0 - metalnessFactor );
vec3 dxy = max( abs( dFdx( geometryNormal ) ), abs( dFdy( geometryNormal ) ) );
float geometryRoughness = max( max( dxy.x, dxy.y ), dxy.z );
material.specularRoughness = max( roughnessFactor, 0.0525 );material.specularRoughness += geometryRoughness;
material.specularRoughness = min( material.specularRoughness, 1.0 );
#ifdef REFLECTIVITY
	material.specularColor = mix( vec3( MAXIMUM_SPECULAR_COEFFICIENT * pow2( reflectivity ) ), diffuseColor.rgb, metalnessFactor );
#else
	material.specularColor = mix( vec3( DEFAULT_SPECULAR_COEFFICIENT ), diffuseColor.rgb, metalnessFactor );
#endif
#ifdef CLEARCOAT
	material.clearcoat = clearcoat;
	material.clearcoatRoughness = clearcoatRoughness;
	#ifdef USE_CLEARCOATMAP
		material.clearcoat *= texture2D( clearcoatMap, vUv ).x;
	#endif
	#ifdef USE_CLEARCOAT_ROUGHNESSMAP
		material.clearcoatRoughness *= texture2D( clearcoatRoughnessMap, vUv ).y;
	#endif
	material.clearcoat = saturate( material.clearcoat );	material.clearcoatRoughness = max( material.clearcoatRoughness, 0.0525 );
	material.clearcoatRoughness += geometryRoughness;
	material.clearcoatRoughness = min( material.clearcoatRoughness, 1.0 );
#endif
#ifdef USE_SHEEN
	material.sheenColor = sheen;
#endif

GeometricContext geometry;
geometry.position = - vViewPosition;
geometry.normal = normal;
geometry.viewDir = ( isOrthographic ) ? vec3( 0, 0, 1 ) : normalize( vViewPosition );
#ifdef CLEARCOAT
	geometry.clearcoatNormal = clearcoatNormal;
#endif
IncidentLight directLight;
#if ( 0 > 0 ) && defined( RE_Direct )
	PointLight pointLight;
	#if defined( USE_SHADOWMAP ) && 0 > 0
	PointLightShadow pointLightShadow;
	#endif
	
#endif
#if ( 0 > 0 ) && defined( RE_Direct )
	SpotLight spotLight;
	#if defined( USE_SHADOWMAP ) && 0 > 0
	SpotLightShadow spotLightShadow;
	#endif
	
#endif
#if ( 1 > 0 ) && defined( RE_Direct )
	DirectionalLight directionalLight;
	#if defined( USE_SHADOWMAP ) && 0 > 0
	DirectionalLightShadow directionalLightShadow;
	#endif
	
		directionalLight = directionalLights[ 0 ];
		getDirectionalDirectLightIrradiance( directionalLight, geometry, directLight );
		#if defined( USE_SHADOWMAP ) && ( 0 < 0 )
		directionalLightShadow = directionalLightShadows[ 0 ];
		directLight.color *= all( bvec2( directLight.visible, receiveShadow ) ) ? getShadow( directionalShadowMap[ 0 ], directionalLightShadow.shadowMapSize, directionalLightShadow.shadowBias, directionalLightShadow.shadowRadius, vDirectionalShadowCoord[ 0 ] ) : 1.0;
		#endif
		RE_Direct( directLight, geometry, material, reflectedLight );
	
#endif
#if ( 0 > 0 ) && defined( RE_Direct_RectArea )
	RectAreaLight rectAreaLight;
	
#endif
#if defined( RE_IndirectDiffuse )
	vec3 iblIrradiance = vec3( 0.0 );
	vec3 irradiance = getAmbientLightIrradiance( ambientLightColor );
	irradiance += getLightProbeIrradiance( lightProbe, geometry );
	#if ( 0 > 0 )
		
	#endif
#endif
#if defined( RE_IndirectSpecular )
	vec3 radiance = vec3( 0.0 );
	vec3 clearcoatRadiance = vec3( 0.0 );
#endif
#if defined( RE_IndirectDiffuse )
	#ifdef USE_LIGHTMAP
		vec4 lightMapTexel= texture2D( lightMap, vUv2 );
		vec3 lightMapIrradiance = lightMapTexelToLinear( lightMapTexel ).rgb * lightMapIntensity;
		#ifndef PHYSICALLY_CORRECT_LIGHTS
			lightMapIrradiance *= PI;
		#endif
		irradiance += lightMapIrradiance;
	#endif
	#if defined( USE_ENVMAP ) && defined( STANDARD ) && defined( ENVMAP_TYPE_CUBE_UV )
		iblIrradiance += getLightProbeIndirectIrradiance( geometry, maxMipLevel );
	#endif
#endif
#if defined( USE_ENVMAP ) && defined( RE_IndirectSpecular )
	radiance += getLightProbeIndirectRadiance( geometry.viewDir, geometry.normal, material.specularRoughness, maxMipLevel );
	#ifdef CLEARCOAT
		clearcoatRadiance += getLightProbeIndirectRadiance( geometry.viewDir, geometry.clearcoatNormal, material.clearcoatRoughness, maxMipLevel );
	#endif
#endif
#if defined( RE_IndirectDiffuse )
	RE_IndirectDiffuse( irradiance, geometry, material, reflectedLight );
#endif
#if defined( RE_IndirectSpecular )
	RE_IndirectSpecular( radiance, iblIrradiance, clearcoatRadiance, geometry, material, reflectedLight );
#endif
	// modulation
#ifdef USE_AOMAP
	float ambientOcclusion = ( texture2D( aoMap, vUv2 ).r - 1.0 ) * aoMapIntensity + 1.0;
	reflectedLight.indirectDiffuse *= ambientOcclusion;
	#if defined( USE_ENVMAP ) && defined( STANDARD )
		float dotNV = saturate( dot( geometry.normal, geometry.viewDir ) );
		reflectedLight.indirectSpecular *= computeSpecularOcclusion( dotNV, ambientOcclusion, material.specularRoughness );
	#endif
#endif
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + reflectedLight.directSpecular + reflectedLight.indirectSpecular + totalEmissiveRadiance;
	// this is a stub for the transparency model
	#ifdef TRANSPARENCY
		diffuseColor.a *= saturate( 1. - transparency + linearToRelativeLuminance( reflectedLight.directSpecular + reflectedLight.indirectSpecular ) );
	#endif
	gl_FragColor = vec4( outgoingLight, diffuseColor.a );
#if defined( TONE_MAPPING )
	gl_FragColor.rgb = toneMapping( gl_FragColor.rgb );
#endif
gl_FragColor = linearToOutputTexel( gl_FragColor );
#ifdef USE_FOG
	#ifdef FOG_EXP2
		float fogFactor = 1.0 - exp( - fogDensity * fogDensity * fogDepth * fogDepth );
	#else
		float fogFactor = smoothstep( fogNear, fogFar, fogDepth );
	#endif
	gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );
#endif
#ifdef PREMULTIPLIED_ALPHA
	gl_FragColor.rgb *= gl_FragColor.a;
#endif
#ifdef DITHERING
	gl_FragColor.rgb = dithering( gl_FragColor.rgb );
#endif
  // float height = sampleHeight(heightmap, refinedUv);
  // // vec2 properuv = vUv;
  // // properuv.y = 1.0 - properuv.y;
  // // vec2 shifts = properuv - refinedUv;
  // gl_FragColor = vec4(height/maxHeight, height/maxHeight, height/maxHeight, 1.0);
}