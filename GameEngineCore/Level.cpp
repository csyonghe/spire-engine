#include "Engine.h"
#include "Level.h"
#include "CoreLib/LibIO.h"
#include "CoreLib/Tokenizer.h"

namespace GameEngine
{
	using namespace CoreLib;
	using namespace CoreLib::IO;

	Level::Level(const CoreLib::String & fileName)
	{
		LoadFromText(File::ReadAllText(fileName));
		
	}
	void Level::LoadFromText(CoreLib::String text)
	{
		Text::TokenReader parser(text);
		while (!parser.IsEnd())
		{
			auto pos = parser.NextToken().Position;
			auto actor = Engine::Instance()->ParseActor(this, parser);
			if (!actor)
			{
				Print("error: ignoring object at line %d.\n", pos.Line);
			}
			else
			{
				try
				{
					RegisterActor(actor.Ptr());
					if (actor->GetEngineType() == EngineActorType::Camera)
						CurrentCamera = actor.As<CameraActor>();
				}
				catch (Exception)
				{
					Print("error: an actor named '%S' already exists, ignoring second actor.\n", actor->Name.ToWString());
				}
			}
		}
		Print("Num materials: %d\n", Materials.Count());
	}
	Level::~Level()
	{
		for (auto & actor : From(Actors).ToList())
			UnregisterActor(actor.Value.Ptr());
	}
	void Level::RegisterActor(Actor * actor)
	{
		Actors.Add(actor->Name, actor);
		actor->OnLoad();
		actor->RegisterUI(Engine::Instance()->GetUiEntry());
	}
	void Level::UnregisterActor(Actor*actor)
	{
		actor->OnUnload();
        auto actorName = actor->Name;
		Actors[actorName] = nullptr;
		Actors.Remove(actorName);
	}
	Mesh * Level::LoadMesh(CoreLib::String fileName)
	{
		RefPtr<Mesh> result = nullptr;
		if (!Meshes.TryGetValue(fileName, result))
		{
			auto actualName = Engine::Instance()->FindFile(fileName, ResourceType::Mesh);
			if (actualName.Length())
			{
				result = new Mesh();
				result->LoadFromFile(actualName);
				Meshes[fileName] = result;
			}
			else
			{
				Print("error: cannot load mesh \'%S\'\n", fileName.ToWString());
				return nullptr;
			}
		}
		return result.Ptr();
	}
	Mesh * Level::LoadMesh(CoreLib::String name, Mesh m)
	{
		RefPtr<Mesh> result = nullptr;
		if (!Meshes.TryGetValue(name, result))
		{
			result = new Mesh(_Move(m));
			Meshes.Add(_Move(name), result);
		}
		return result.Ptr();
	}
	Skeleton * Level::LoadSkeleton(const CoreLib::String & fileName)
	{
		RefPtr<Skeleton> result = nullptr;
		if (!Skeletons.TryGetValue(fileName, result))
		{
			auto actualName = Engine::Instance()->FindFile(fileName, ResourceType::Mesh);
			if (actualName.Length())
			{
				result = new Skeleton();
				result->LoadFromFile(actualName);
				Skeletons[fileName] = result;
			}
			else
			{
				Print("error: cannot load skeleton \'%S\'\n", fileName.ToWString());
				return nullptr;
			}
		}
		return result.Ptr();
	}
	RetargetFile * Level::LoadRetargetFile(const CoreLib::String & fileName)
	{
		auto result = RetargetFiles.TryGetValue(fileName);
		if (!result)
		{
			auto actualName = Engine::Instance()->FindFile(fileName, ResourceType::Mesh);
			if (actualName.Length())
			{
				RetargetFile file;
				file.LoadFromFile(actualName);
				RetargetFiles[fileName] = _Move(file);
			}
			else
				return nullptr;
		}
		return RetargetFiles.TryGetValue(fileName);
	}
	Material * Level::LoadMaterial(const CoreLib::String & fileName)
	{
		RefPtr<Material> result = nullptr;
		if (!Materials.TryGetValue(fileName, result))
		{
			auto actualName = Engine::Instance()->FindFile(fileName, ResourceType::Material);
			if (actualName.Length())
			{
				result = new Material();
				result->LoadFromFile(actualName);
				Materials[fileName] = result;
			}
			else if (fileName != "Error.material")
			{
				Print("error: cannot load material \'%S\'\n", fileName.ToWString());
				return LoadMaterial("Error.material");
			}
			else
				return nullptr;
		}
		return result.Ptr();
	}
	Material * Level::CreateNewMaterial()
	{
		Material* mat = new Material();
		Materials[String("$materialInstance") + String(Materials.Count())] = mat;
		return mat;
	}
	SkeletalAnimation * Level::LoadSkeletalAnimation(const CoreLib::String & fileName)
	{
		RefPtr<SkeletalAnimation> result = nullptr;
		if (!Animations.TryGetValue(fileName, result))
		{
			auto actualName = Engine::Instance()->FindFile(fileName, ResourceType::Mesh);
			if (actualName.Length())
			{
				result = new SkeletalAnimation();
				result->LoadFromFile(actualName);
				Animations[fileName] = result;
			}
			else
			{
				Print("error: cannot load animation \'%S\'\n", fileName.ToWString());
				return nullptr;
			}
		}
		return result.Ptr();
	}
	Actor * Level::FindActor(const CoreLib::String & name)
	{
		RefPtr<Actor> result;
		Actors.TryGetValue(name, result);
		return result.Ptr();
	}
}
