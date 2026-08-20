#define TEXTURECOUNT 1
#define VERTEXGROUPCOUNT0 3

ModelFileTextures proptextures[TEXTURECOUNT] = {
    {0x05000020, 8, 8, 0x02, 0x00, 0x02, 0x00, 0x00},
};

ModelNode ModelNode_0x010 = {MODELNODE_OPCODE_GROUP, &GroupRecord_0x020, NULL, NULL, NULL, &ModelNode_0x030};
ModelNode ModelNode_0x030 = {MODELNODE_OPCODE_DL, &DisplayListRecord_0x040, &ModelNode_0x010, NULL, NULL, NULL};

extern Vertex Vertex_0x050[VERTEXGROUPCOUNT0];
extern Gfx GFX_PRIMARY_0x060[];

Gfx GFX_PRIMARY_0x060[] = {
    gsSPVertex(Vertex_0x050, 3, 0),
    gsSPEndDisplayList(),
};
