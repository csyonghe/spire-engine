#ifndef GAME_ENGINE_LEVEL_H
#define GAME_ENGINE_LEVEL_H

#include "CoreLib/Basic.h"
#include "Model.h"
#include "Actor.h"
#include "Material.h"
#include "Skeleton.h"
#include "Physics.h"

namespace GameEngine
{
    class Actor;
    class CameraActor;

    class Level : public CoreLib::Object
    {
    private:
        PhysicsScene physicsScene;
        CoreLib::RefPtr<Model> errorModel;
    public:
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::RefPtr<Material>> Materials;
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::RefPtr<Model>> Models;
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::RefPtr<Mesh>> Meshes;
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::RefPtr<Skeleton>> Skeletons;
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::RefPtr<SkeletalAnimation>> Animations;
        CoreLib::EnumerableDictionary<CoreLib::String, RetargetFile> RetargetFiles;
        CoreLib::EnumerableDictionary<CoreLib::String, CoreLib::ObjPtr<Actor>> Actors;
        CoreLib::List<CoreLib::String> HiddenSections;
        CoreLib::ObjPtr<CameraActor> CurrentCamera;
        CoreLib::String FileName;
        CoreLib::String LightmapFileName;
        void LoadFromText(CoreLib::String text);
        void SaveToFile(CoreLib::String fileName);
        Level(const CoreLib::String & fileName);
        Level() = default;
        ~Level();
        Mesh * LoadMesh(CoreLib::String fileName);
        Mesh * LoadMesh(CoreLib::String name, Mesh m);
        Mesh * LoadErrorMesh();
        Model * LoadModel(CoreLib::String fileName);
        Model * LoadErrorModel();
        Skeleton * LoadSkeleton(const CoreLib::String & fileName);
        RetargetFile * LoadRetargetFile(const CoreLib::String & fileName);
        Material * LoadMaterial(const CoreLib::String & fileName);
        Material * LoadErrorMaterial();
        Material * CreateNewMaterial();
        SkeletalAnimation * LoadSkeletalAnimation(const CoreLib::String & fileName);
        Actor * FindActor(const CoreLib::String & name);
        PhysicsScene & GetPhysicsScene()
        {
            return physicsScene;
        }
        void RegisterActor(Actor * actor);
        void UnregisterActor(Actor * actor);
    };
}

#endif