#include "ArcBallCameraController.h"
#include "Engine.h"
#include "CameraActor.h"

namespace GameEngine
{
	using namespace VectorMath;

	ArcBallParams ArcBallCameraControllerActor::GetCurrentArcBall()
	{
		ArcBallParams rs;
		rs.radius = Radius.GetValue();
		rs.center = Center.GetValue();
		rs.alpha = Alpha.GetValue();
		rs.beta = Beta.GetValue();
		return rs;
	}

	void ArcBallCameraControllerActor::FindTargetCamera()
	{
		auto actor = level->FindActor(TargetCameraName.GetValue());
		if (actor && actor->GetEngineType() == EngineActorType::Camera)
			targetCamera = (CameraActor*)actor;
	}

	void ArcBallCameraControllerActor::UpdateCamera()
	{
		if (targetCamera)
		{
			Vec3 camPos, up, right, dir;
			auto currentArcBall = GetCurrentArcBall();
			currentArcBall.GetCoordinates(camPos, up, right, dir);
			targetCamera->SetPosition(camPos);
			float rotX = asinf(-dir.y);
			float rotY = -atan2f(-dir.x, -dir.z);
			targetCamera->SetOrientation(rotY, rotX, 0.0f);
		}
	}

	void ArcBallCameraControllerActor::MouseDown(GraphicsUI::UI_Base * /*sender*/, GraphicsUI::UIMouseEventArgs & e)
	{
		auto currentArcBall = GetCurrentArcBall();
		lastArcBall = currentArcBall;
		auto altMask = NeedAlt.GetValue() ? GraphicsUI::SS_ALT : 0;
		auto leftAltMask = (altMask | GraphicsUI::SS_BUTTONLEFT);
		auto rightAltMask = (altMask | GraphicsUI::SS_BUTTONRIGHT);
		lastX = e.X;
		lastY = e.Y;
		if ((e.Shift & leftAltMask) == leftAltMask)
		{
			state = MouseState::Rotate;
		}
		else if ((e.Shift & rightAltMask) == rightAltMask)
		{
			state = MouseState::Translate;
		}
		else
			state = MouseState::None;
	}

	void ArcBallCameraControllerActor::MouseMove(GraphicsUI::UI_Base * /*sender*/, GraphicsUI::UIMouseEventArgs & e)
	{
		FindTargetCamera();
		if (targetCamera)
		{
			int deltaX = e.X - lastX;
			int deltaY = e.Y - lastY;
			if (state == MouseState::Rotate)
			{
				Alpha = lastArcBall.alpha + deltaX * this->TurnPrecision.GetValue();
				Beta = lastArcBall.beta + deltaY * this->TurnPrecision.GetValue();
                Beta = Math::Clamp(*Beta, -Math::Pi*0.5f + 1e-4f, Math::Pi*0.5f - 1e-4f);
			}
			else if (state == MouseState::Translate)
			{
				Vec3 camPos, up, right, dir;
				auto currentArcBall = GetCurrentArcBall();
				currentArcBall.GetCoordinates(camPos, up, right, dir);
				Center = lastArcBall.center + up * TranslatePrecision.GetValue() * currentArcBall.radius * (float)deltaY
					- right * TranslatePrecision.GetValue() * currentArcBall.radius * (float)deltaX;
			}
			UpdateCamera();
		}
	}


	void ArcBallCameraControllerActor::MouseUp(GraphicsUI::UI_Base * /*sender*/, GraphicsUI::UIMouseEventArgs & /*e*/)
	{
		state = MouseState::None;
	}

	void ArcBallCameraControllerActor::MouseWheel(GraphicsUI::UI_Base * /*sender*/, GraphicsUI::UIMouseEventArgs & e)
	{
		if (e.Delta < 0)
			Radius = Radius.GetValue() * ZoomScale.GetValue();
		else
			Radius = Radius.GetValue() / ZoomScale.GetValue();
		Radius = Math::Clamp(Radius.GetValue(), MinDist.GetValue(), MaxDist.GetValue());
		FindTargetCamera();
		UpdateCamera();
	}

	void ArcBallCameraControllerActor::OnLoad()
	{
		Actor::OnLoad();
		if (Engine::Instance()->GetEngineMode() != EngineMode::Editor)
		{
			Engine::Instance()->GetUiEntry()->OnMouseDown.Bind(this, &ArcBallCameraControllerActor::MouseDown);
			Engine::Instance()->GetUiEntry()->OnMouseMove.Bind(this, &ArcBallCameraControllerActor::MouseMove);
			Engine::Instance()->GetUiEntry()->OnMouseUp.Bind(this, &ArcBallCameraControllerActor::MouseUp);
			Engine::Instance()->GetUiEntry()->OnMouseWheel.Bind(this, &ArcBallCameraControllerActor::MouseWheel);
			Engine::Instance()->GetInputDispatcher()->BindActionHandler("dumpcam", ActionInputHandlerFunc(this, &ArcBallCameraControllerActor::DumpCamera));
		}
		FindTargetCamera();
		UpdateCamera();
	}

	void ArcBallCameraControllerActor::OnUnload()
	{
		if (Engine::Instance()->GetEngineMode() != EngineMode::Editor)
		{
			Engine::Instance()->GetUiEntry()->OnMouseDown.Unbind(this, &ArcBallCameraControllerActor::MouseDown);
			Engine::Instance()->GetUiEntry()->OnMouseMove.Unbind(this, &ArcBallCameraControllerActor::MouseMove);
			Engine::Instance()->GetUiEntry()->OnMouseUp.Unbind(this, &ArcBallCameraControllerActor::MouseUp);
			Engine::Instance()->GetUiEntry()->OnMouseWheel.Unbind(this, &ArcBallCameraControllerActor::MouseWheel);
			Engine::Instance()->GetInputDispatcher()->UnbindActionHandler("dumpcam", ActionInputHandlerFunc(this, &ArcBallCameraControllerActor::DumpCamera));
		}
	}

	EngineActorType ArcBallCameraControllerActor::GetEngineType()
	{
		return EngineActorType::UserController;
	}

	void ArcBallCameraControllerActor::SetCenter(VectorMath::Vec3 p)
	{
		Center = p;
		FindTargetCamera();
		UpdateCamera();
	}

	bool ArcBallCameraControllerActor::DumpCamera(const CoreLib::String & /*axisName*/, ActionInput /*input*/)
	{
		Print("center [%.3f, %.3f, %.3f]\n", Center->x, Center->y, Center->z);
		Print("radius %.3f\n", Radius.GetValue());
		Print("alpha %.3f\n", Alpha.GetValue());
		Print("beta %.3f\n", Beta.GetValue());
		return true;
	}
	void ArcBallParams::GetCoordinates(VectorMath::Vec3 & camPos, VectorMath::Vec3 & up, VectorMath::Vec3 & right, VectorMath::Vec3 & dir)
	{
		Vec3 axisDir;
		axisDir.x = cos(alpha) * cos(beta);
		axisDir.z = sin(alpha) * cos(beta);
		axisDir.y = sin(beta);
		dir = -axisDir;
        float beta2 = beta + Math::Pi * 0.5f;
		up.x = cos(alpha) * cos(beta2);
		up.z = sin(alpha) * cos(beta2);
		up.y = sin(beta2);
		right = Vec3::Cross(dir, up);
		camPos = center + axisDir * radius;
	}
}
