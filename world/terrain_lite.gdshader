shader_type spatial;
// Version légère pour téléphones : lumière calculée aux sommets, sans relief fin ni reflets.
render_mode diffuse_lambert, specular_disabled, vertex_lighting;
#define LITE
#include "res://world/terrain.gdshaderinc"
