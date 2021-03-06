#ifndef GAME_ENGINE_RASTERIZER_H
#define GAME_ENGINE_RASTERIZER_H

#include "CoreLib/VectorMath.h"
#include "CoreLib/Basic.h"

namespace GameEngine
{
    class ProjectedTriangle
    {
    public:
        int X0, Y0;
        int X1, Y1;
        int X2, Y2;
        int A0, B0, A1, B1, A2, B2;
        int C0, C1, C2;
    };
    // sets up the triangle based on three post-projection clip space coordinates.
    // it computes the edges equation and perform back-face culling. 
    struct Canvas
    {
        CoreLib::IntSet bitmap;
        int width, height;
        void Init(int w, int h)
        {
            width = w;
            height = h;
            bitmap.SetMax(w * h);
        }
        void Set(int x, int y)
        {
            bitmap.Add(y * width + x);
        }
        bool Get(int x, int y)
        {
            return bitmap.Contains(y * width + x);
        }
    };
    class Rasterizer
    {
    public:
        static bool SetupTriangle(ProjectedTriangle & tri, VectorMath::Vec2 s0, VectorMath::Vec2 s1, VectorMath::Vec2 s2, int width, int height, int dilate = 8);
        static int CountOverlap(Canvas& canvas, ProjectedTriangle & tri);
        static void Rasterize(Canvas& canvas, ProjectedTriangle & tri);
    };
}

#endif