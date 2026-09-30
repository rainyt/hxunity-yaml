package hxunity.yaml;

/**
	Unity `!u!` class ids and their names.

	The id is what appears in a document header (`--- !u!114 &1234`), the name is
	the single top level key of the document body. Both are needed: the id is
	stable across Unity versions and is what a `fileID` reference resolves
	against, while the name is what a human reads in the file.

	The table covers every id Unity 2022.3 can serialise into a `.prefab`,
	`.asset`, `.unity`, `.controller` or `.mat` file. An id that is absent is not
	an error: the reader keeps the id and recovers the name from the document
	body instead.
**/
class ClassIds
{
	// Core object graph.
	public static inline var GameObject = 1;
	public static inline var Component = 2;
	public static inline var LevelGameManager = 3;
	public static inline var Transform = 4;
	public static inline var TimeManager = 5;
	public static inline var GlobalGameManager = 6;
	public static inline var Behaviour = 8;
	public static inline var GameManager = 9;
	public static inline var AudioManager = 11;
	public static inline var InputManager = 13;
	public static inline var EditorExtension = 18;
	public static inline var Physics2DSettings = 19;
	public static inline var Camera = 20;
	public static inline var Material = 21;
	public static inline var MeshRenderer = 23;
	public static inline var Renderer = 25;
	public static inline var Texture = 27;
	public static inline var Texture2D = 28;
	public static inline var OcclusionCullingSettings = 29;
	public static inline var GraphicsSettings = 30;
	public static inline var MeshFilter = 33;
	public static inline var Mesh = 43;
	public static inline var Skybox = 45;
	public static inline var QualitySettings = 47;
	public static inline var Shader = 48;
	public static inline var TextAsset = 49;
	public static inline var Rigidbody2D = 50;
	public static inline var Rigidbody = 54;
	public static inline var PhysicsManager = 55;
	public static inline var Collider = 56;
	public static inline var Joint = 57;
	public static inline var CircleCollider2D = 58;
	public static inline var HingeJoint = 59;
	public static inline var PolygonCollider2D = 60;
	public static inline var BoxCollider2D = 61;
	public static inline var EdgeCollider2D = 64;
	public static inline var BoxCollider = 65;
	public static inline var CompositeCollider2D = 66;
	public static inline var MeshCollider = 67;
	public static inline var AnimationClip = 74;
	public static inline var ConstantForce = 75;
	public static inline var TagManager = 78;
	public static inline var LayerManager = 80;
	public static inline var AudioListener = 81;
	public static inline var AudioSource = 82;
	public static inline var AudioClip = 83;
	public static inline var RenderTexture = 84;
	public static inline var Cubemap = 89;
	public static inline var Avatar = 90;
	public static inline var AnimatorController = 91;
	public static inline var GUILayer = 92;
	public static inline var RuntimeAnimatorController = 93;
	public static inline var Animator = 95;
	public static inline var TrailRenderer = 96;
	public static inline var TextMesh = 102;
	public static inline var RenderSettings = 104;
	public static inline var Light = 108;
	public static inline var ShaderVariantCollection = 111;
	public static inline var MonoBehaviour = 114;
	public static inline var MonoScript = 115;
	public static inline var MonoManager = 116;
	public static inline var Projector = 120;
	public static inline var LineRenderer = 120;
	public static inline var Flare = 121;
	public static inline var Halo = 122;
	public static inline var LensFlare = 123;
	public static inline var FlareLayer = 124;
	public static inline var HaloLayer = 125;
	public static inline var NavMeshProjectSettings = 126;
	public static inline var Font = 128;
	public static inline var PlayerSettings = 129;
	public static inline var NamedObject = 130;
	public static inline var SphereCollider = 135;
	public static inline var CapsuleCollider = 136;
	public static inline var CharacterController = 143;
	public static inline var CharacterJoint = 144;
	public static inline var SpringJoint = 145;
	public static inline var WheelCollider = 146;
	public static inline var FixedJoint = 153;
	public static inline var ConfigurableJoint = 154;
	public static inline var TerrainCollider = 155;
	public static inline var TerrainData = 156;
	public static inline var LightmapSettings = 157;
	public static inline var AudioBehaviour = 180;
	public static inline var Cloth = 183;
	public static inline var NavMeshSettings = 196;
	public static inline var ParticleSystem = 198;
	public static inline var ParticleSystemRenderer = 199;
	public static inline var BlendTree = 206;
	public static inline var SortingGroup = 210;
	public static inline var SpriteRenderer = 212;
	public static inline var Sprite = 213;
	public static inline var ReflectionProbe = 215;
	public static inline var Terrain = 218;
	public static inline var LightProbeGroup = 220;
	public static inline var AnimatorOverrideController = 221;
	public static inline var CanvasRenderer = 222;
	public static inline var Canvas = 223;
	public static inline var RectTransform = 224;
	public static inline var CanvasGroup = 225;
	public static inline var HingeJoint2D = 230;
	public static inline var DistanceJoint2D = 232;
	public static inline var FixedJoint2D = 233;
	public static inline var SliderJoint2D = 234;
	public static inline var WheelJoint2D = 235;
	public static inline var AudioDistortionFilter = 242;
	public static inline var AudioChorusFilter = 243;
	public static inline var AudioLowPassFilter = 245;
	public static inline var AudioHighPassFilter = 246;
	public static inline var AudioEchoFilter = 247;
	public static inline var AudioReverbZone = 248;
	public static inline var AudioReverbFilter = 249;
	public static inline var AudioSpatializer = 312;
	public static inline var VideoPlayer = 328;
	public static inline var VideoClip = 329;
	public static inline var SpriteMask = 331;
	public static inline var PrefabInstance = 1001;
	public static inline var PrefabAsset = 1002;
	public static inline var AnimatorStateTransition = 1101;
	public static inline var AnimatorState = 1102;
	public static inline var AnimatorStateMachine = 1107;

	/** Synthetic id Unity uses for the `SceneRoots` document of a scene. **/
	public static inline var SceneRoots = 1660057539;

	public static var names(default, null):Map<Int, String> = buildNames();

	static function buildNames():Map<Int, String>
	{
		var map = new Map<Int, String>();
		map.set(0, "Document");
		map.set(GameObject, "GameObject");
		map.set(Component, "Component");
		map.set(Transform, "Transform");
		map.set(TimeManager, "TimeManager");
		map.set(GlobalGameManager, "GlobalGameManager");
		map.set(Behaviour, "Behaviour");
		map.set(GameManager, "GameManager");
		map.set(AudioManager, "AudioManager");
		map.set(InputManager, "InputManager");
		map.set(EditorExtension, "EditorExtension");
		map.set(Physics2DSettings, "Physics2DSettings");
		map.set(Camera, "Camera");
		map.set(Material, "Material");
		map.set(MeshRenderer, "MeshRenderer");
		map.set(Renderer, "Renderer");
		map.set(Texture, "Texture");
		map.set(Texture2D, "Texture2D");
		map.set(OcclusionCullingSettings, "OcclusionCullingSettings");
		map.set(GraphicsSettings, "GraphicsSettings");
		map.set(MeshFilter, "MeshFilter");
		map.set(Mesh, "Mesh");
		map.set(Skybox, "Skybox");
		map.set(QualitySettings, "QualitySettings");
		map.set(Shader, "Shader");
		map.set(TextAsset, "TextAsset");
		map.set(Rigidbody2D, "Rigidbody2D");
		map.set(Rigidbody, "Rigidbody");
		map.set(PhysicsManager, "PhysicsManager");
		map.set(Collider, "Collider");
		map.set(Joint, "Joint");
		map.set(CircleCollider2D, "CircleCollider2D");
		map.set(HingeJoint, "HingeJoint");
		map.set(PolygonCollider2D, "PolygonCollider2D");
		map.set(BoxCollider2D, "BoxCollider2D");
		map.set(EdgeCollider2D, "EdgeCollider2D");
		map.set(BoxCollider, "BoxCollider");
		map.set(CompositeCollider2D, "CompositeCollider2D");
		map.set(MeshCollider, "MeshCollider");
		map.set(AnimationClip, "AnimationClip");
		map.set(ConstantForce, "ConstantForce");
		map.set(TagManager, "TagManager");
		map.set(LayerManager, "LayerManager");
		map.set(AudioListener, "AudioListener");
		map.set(AudioSource, "AudioSource");
		map.set(AudioClip, "AudioClip");
		map.set(RenderTexture, "RenderTexture");
		map.set(Cubemap, "Cubemap");
		map.set(Avatar, "Avatar");
		map.set(AnimatorController, "AnimatorController");
		map.set(GUILayer, "GUILayer");
		map.set(RuntimeAnimatorController, "RuntimeAnimatorController");
		map.set(Animator, "Animator");
		map.set(TrailRenderer, "TrailRenderer");
		map.set(TextMesh, "TextMesh");
		map.set(RenderSettings, "RenderSettings");
		map.set(Light, "Light");
		map.set(ShaderVariantCollection, "ShaderVariantCollection");
		map.set(MonoBehaviour, "MonoBehaviour");
		map.set(MonoScript, "MonoScript");
		map.set(MonoManager, "MonoManager");
		map.set(Projector, "Projector");
		map.set(LineRenderer, "LineRenderer");
		map.set(Flare, "Flare");
		map.set(Halo, "Halo");
		map.set(LensFlare, "LensFlare");
		map.set(FlareLayer, "FlareLayer");
		map.set(HaloLayer, "HaloLayer");
		map.set(NavMeshProjectSettings, "NavMeshProjectSettings");
		map.set(Font, "Font");
		map.set(PlayerSettings, "PlayerSettings");
		map.set(NamedObject, "NamedObject");
		map.set(SphereCollider, "SphereCollider");
		map.set(CapsuleCollider, "CapsuleCollider");
		map.set(CharacterController, "CharacterController");
		map.set(CharacterJoint, "CharacterJoint");
		map.set(SpringJoint, "SpringJoint");
		map.set(WheelCollider, "WheelCollider");
		map.set(FixedJoint, "FixedJoint");
		map.set(ConfigurableJoint, "ConfigurableJoint");
		map.set(TerrainCollider, "TerrainCollider");
		map.set(TerrainData, "TerrainData");
		map.set(LightmapSettings, "LightmapSettings");
		map.set(AudioBehaviour, "AudioBehaviour");
		map.set(Cloth, "Cloth");
		map.set(NavMeshSettings, "NavMeshSettings");
		map.set(ParticleSystem, "ParticleSystem");
		map.set(ParticleSystemRenderer, "ParticleSystemRenderer");
		map.set(BlendTree, "BlendTree");
		map.set(SortingGroup, "SortingGroup");
		map.set(SpriteRenderer, "SpriteRenderer");
		map.set(Sprite, "Sprite");
		map.set(ReflectionProbe, "ReflectionProbe");
		map.set(Terrain, "Terrain");
		map.set(LightProbeGroup, "LightProbeGroup");
		map.set(AnimatorOverrideController, "AnimatorOverrideController");
		map.set(CanvasRenderer, "CanvasRenderer");
		map.set(Canvas, "Canvas");
		map.set(RectTransform, "RectTransform");
		map.set(CanvasGroup, "CanvasGroup");
		map.set(HingeJoint2D, "HingeJoint2D");
		map.set(DistanceJoint2D, "DistanceJoint2D");
		map.set(FixedJoint2D, "FixedJoint2D");
		map.set(SliderJoint2D, "SliderJoint2D");
		map.set(WheelJoint2D, "WheelJoint2D");
		map.set(AudioDistortionFilter, "AudioDistortionFilter");
		map.set(AudioChorusFilter, "AudioChorusFilter");
		map.set(AudioLowPassFilter, "AudioLowPassFilter");
		map.set(AudioHighPassFilter, "AudioHighPassFilter");
		map.set(AudioEchoFilter, "AudioEchoFilter");
		map.set(AudioReverbZone, "AudioReverbZone");
		map.set(AudioReverbFilter, "AudioReverbFilter");
		map.set(AudioSpatializer, "AudioSpatializer");
		map.set(VideoPlayer, "VideoPlayer");
		map.set(VideoClip, "VideoClip");
		map.set(SpriteMask, "SpriteMask");
		map.set(PrefabInstance, "PrefabInstance");
		map.set(PrefabAsset, "PrefabAsset");
		map.set(AnimatorStateTransition, "AnimatorStateTransition");
		map.set(AnimatorState, "AnimatorState");
		map.set(AnimatorStateMachine, "AnimatorStateMachine");
		map.set(SceneRoots, "SceneRoots");
		return map;
	}

	/**
		Class name for [classId], or `null` when the id is not in the table.

		Callers should prefer [UnityYamlDocument.className], which falls back to
		the class name found in the document body.
	**/
	public static function name(classId:Int):String
	{
		return names.get(classId);
	}

	/** Class id for [className], or -1 when the name is not in the table. **/
	public static function id(className:String):Int
	{
		for (key => value in names)
		{
			if (value == className) return key;
		}
		return -1;
	}

	/**
		True when [classId] is an object a `GameObject` lists in `m_Component`.

		`Transform` and `RectTransform` count: Unity lists the transform first in
		`m_Component`, so a caller walking the components of an object expects to
		find it. `GameObject`, `PrefabInstance` and the synthetic `SceneRoots` do
		not, because they are the objects that own or reference components rather
		than being one.
	**/
	public static function isComponent(classId:Int):Bool
	{
		return classId != GameObject && classId != PrefabInstance && classId != SceneRoots;
	}

	/**
		True when [classId] derives from Unity's `Behaviour`.

		Behaviours serialise `m_Enabled`, which is why creating one needs that
		field but creating a `MeshFilter` does not. Ids are listed in a table rather
		than a `switch` so two names that happen to share a value cannot silently
		drop a case.
	**/
	public static function isBehaviour(classId:Int):Bool
	{
		if (behaviours == null)
		{
			behaviours = new Map();
			for (id in [
				MonoBehaviour, Animator, AudioSource, AudioListener, Camera, Light, ParticleSystem, TrailRenderer, LineRenderer,
				Canvas, CanvasGroup, VideoPlayer, Projector, FlareLayer, Halo, Cloth, ConstantForce, AudioReverbZone,
				AudioLowPassFilter, AudioHighPassFilter, AudioEchoFilter, AudioDistortionFilter, AudioReverbFilter,
				AudioChorusFilter
			])
			{
				behaviours.set(id, true);
			}
		}
		return behaviours.exists(classId);
	}

	static var behaviours:Map<Int, Bool>;
}
