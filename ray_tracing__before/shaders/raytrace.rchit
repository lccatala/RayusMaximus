#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_buffer_reference2 : require
#include "raycommon.glsl"
#include "wavefront.glsl"

// Describe resources according to the descriptor set layout
layout(location = 0) rayPayloadInEXT hitPayload prd;
hitAttributeEXT vec2 attribs;

layout(buffer_reference, scalar) buffer Vertices { Vertex v[]; }; // Positions of an object
layout(buffer_reference, scalar) buffer Indices { ivec3 i[]; }; // Triangle indices
layout(buffer_reference, scalar) buffer Materials { WaveFrontMaterial m[]; }; // Array of all materials on an object
layout(buffer_reference, scalar) buffer MatIndices { int i[]; }; // Material ID for each triangle
layout(set = 1, binding = eObjDescs, scalar) buffer ObjDesc_ { ObjDesc i[]; } objDesc;
layout(set = 1, binding = eTextures) uniform sampler2D textureSamplers[];

layout(push_constant) uniform _PushConstantRay { PushConstantRay pcRay; };


// gl_InstanceCustomIndexEXT -> which object was hit
// gl_PrimitiveID -> find the vertices of the triangle hit by the ray
void main()
{
  // Object data
  ObjDesc objResource = objDesc.i[gl_InstanceCustomIndexEXT];
  MatIndices matIndices = MatIndices(objResource.materialIndexAddress);
  Materials materials = Materials(objResource.materialAddress);
  Indices indices = Indices(objResource.indexAddress);
  Vertices vertices = Vertices(objResource.vertexAddress);

  // Indices of the triangle
  ivec3 ind = indices.i[gl_PrimitiveID];

  // Vertices of the triangle
  Vertex v0 = vertices.v[ind.x];
  Vertex v1 = vertices.v[ind.y];
  Vertex v2 = vertices.v[ind.z];
  
  const vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
  
  // Use interpolation to calculate hit position, more precise for far away points
  const vec3 pos = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
  const vec3 worldPos = vec3(gl_ObjectToWorldEXT * vec4(pos, 1.0)); // Position to world space

  // Same method to compute normal at hit position
  const vec3 nrm = v0.nrm * barycentrics.x + v1.nrm * barycentrics.y + v2.nrm * barycentrics.z;
  const vec3 worldNrm = normalize(vec3(nrm * gl_WorldToObjectEXT)); // Normal to world space

  // Dot product of normal with light direction for simple lighting
  vec3 L;
  float lightIntensity = pcRay.lightIntensity;
  float lightDistance = 100000.0;

  // Point light
  if (pcRay.lightType == 0)
  {
    vec3 lDir = pcRay.lightPosition - worldPos;
    lightDistance = length(lDir);
    lightIntensity = pcRay.lightIntensity / (lightDistance * lightDistance);
    L = normalize(lDir);
  }
  else // Directional light
  {
    L = normalize(pcRay.lightPosition);
  }

  // Material of the object
  int matIdx = matIndices.i[gl_PrimitiveID];
  WaveFrontMaterial mat = materials.m[matIdx];

  // Diffuse
  vec3 diffuse = computeDiffuse(mat, L, worldNrm);
  if (mat.textureId >= 0)
  {
    uint txtId = mat.textureId + objDesc.i[gl_InstanceCustomIndexEXT].txtOffset;
    vec2 texCoord = v0.texCoord * barycentrics.x + v1.texCoord * barycentrics.y + v2.texCoord * barycentrics.z;
    diffuse *= texture(textureSamplers[nonuniformEXT(txtId)], texCoord).xyz;
  }

  // Specular
  vec3 specular = computeSpecular(mat, gl_WorldRayDirectionEXT, L, worldNrm);

  prd.hitValue = vec3(lightIntensity * (diffuse + specular));
}

