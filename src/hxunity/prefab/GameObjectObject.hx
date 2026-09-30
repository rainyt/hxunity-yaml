package hxunity.prefab;

import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.ScalarKind;
import hxunity.unity.FileId;
import hxunity.unity.UnityReference;

/**
	A `GameObject`, the node of a prefab's hierarchy.

	The hierarchy Unity serialises is not stored on the GameObject itself: each
	GameObject owns a `Transform`, and transforms hold `m_Father` and `m_Children`.
	This class follows those references, so [children] and [parent] work without
	the caller touching `fileID` values.
**/
class GameObjectObject extends UnityObject
{
	public function new(document:UnityYamlDocument, prefab:UnityPrefab)
	{
		super(document, prefab);
	}

	/** `m_Name`. **/
	public function name():String
	{
		return getString("m_Name");
	}

	/** Sets `m_Name`. **/
	public function setName(value:String):Void
	{
		set("m_Name", new YamlScalar(value, ScalarKind.Plain));
	}

	/** `m_IsActive`, defaulting to true when the field is absent. **/
	public function active():Bool
	{
		var value = getBool("m_IsActive");
		return value == null ? true : value;
	}

	/** Sets `m_IsActive`. **/
	public function setActive(value:Bool):Void
	{
		set("m_IsActive", new YamlScalar(value ? "1" : "0", ScalarKind.Plain));
	}

	/** `m_TagString`. **/
	public function tag():String
	{
		return getString("m_TagString");
	}

	/** Sets `m_TagString`. **/
	public function setTag(value:String):Void
	{
		set("m_TagString", new YamlScalar(value, ScalarKind.Plain));
	}

	/** `m_Layer`. **/
	public function layer():Null<Int>
	{
		return getInt("m_Layer");
	}

	/** Sets `m_Layer`. **/
	public function setLayer(value:Int):Void
	{
		set("m_Layer", new YamlScalar(Std.string(value), ScalarKind.Plain));
	}

	/** `m_Component`, the raw sequence of component references. **/
	public function componentReferences():YamlSeq
	{
		return getSeq("m_Component");
	}

	/**
		Every component of this GameObject, in serialisation order.

		The `Transform` always comes first for a GameObject Unity created.
	**/
	public function components():Array<Component>
	{
		var out = [];
		var list = componentReferences();
		if (list == null) return out;
		for (item in list.items)
		{
			if (!Std.isOfType(item, YamlMap)) continue;
			var entry:YamlMap = cast item;
			var reference = UnityReference.fromNode(entry.get("component"));
			if (reference == null || reference.isExternal()) continue;
			var document = prefab.documents.byId(reference.fileId);
			if (document == null) continue;
			out.push(Component.create(document, prefab));
		}
		return out;
	}

	/** First component whose class id is [classId], or `null`. **/
	public function getComponent(classId:Int):Component
	{
		var list = componentReferences();
		if (list == null) return null;
		for (item in list.items)
		{
			if (!Std.isOfType(item, YamlMap)) continue;
			var entry:YamlMap = cast item;
			var reference = UnityReference.fromNode(entry.get("component"));
			if (reference == null || reference.isExternal()) continue;
			var document = prefab.documents.byId(reference.fileId);
			if (document != null && document.classId == classId)
			{
				return Component.create(document, prefab);
			}
		}
		return null;
	}

	/** Every component whose class id is [classId]. **/
	public function getComponents(classId:Int):Array<Component>
	{
		var out = [];
		for (component in components())
		{
			if (component.classId() == classId) out.push(component);
		}
		return out;
	}

	/** This object's `Transform` or `RectTransform`, or `null`. **/
	public function transform():TransformObject
	{
		for (component in components())
		{
			if (component.classId() == ClassIds.Transform || component.classId() == ClassIds.RectTransform)
			{
				return new TransformObject(component.document, prefab);
			}
		}
		return null;
	}

	/** Parent GameObject in the hierarchy, or `null` for a root object. **/
	public function parent():GameObjectObject
	{
		var transform = this.transform();
		return transform == null ? null : transform.parent();
	}

	/** Direct children, in `m_Children` order. **/
	public function children():Array<GameObjectObject>
	{
		var transform = this.transform();
		return transform == null ? [] : transform.children();
	}

	/** Every descendant, depth first, excluding this object. **/
	public function descendants():Array<GameObjectObject>
	{
		var out = [];
		collectDescendants(out);
		return out;
	}

	function collectDescendants(out:Array<GameObjectObject>):Void
	{
		for (child in children())
		{
			out.push(child);
			child.collectDescendants(out);
		}
	}

	/** Depth of this object in the hierarchy, 0 for a root object. **/
	public function depth():Int
	{
		var level = 0;
		var current = parent();
		while (current != null)
		{
			level++;
			current = current.parent();
		}
		return level;
	}

	/** Path of names from the root to this object, e.g. `Player/Hand/Bone`. **/
	public function path():String
	{
		var parts = [name()];
		var current = parent();
		while (current != null)
		{
			parts.unshift(current.name());
			current = current.parent();
		}
		return parts.join("/");
	}

	/** First descendant (or this object) whose name is [name], or `null`. **/
	public function find(name:String):GameObjectObject
	{
		if (this.name() == name) return this;
		for (child in children())
		{
			var found = child.find(name);
			if (found != null) return found;
		}
		return null;
	}

	/** Every descendant (or this object) whose name is [name]. **/
	public function findAll(name:String):Array<GameObjectObject>
	{
		var out = [];
		if (this.name() == name) out.push(this);
		for (child in children())
		{
			out = out.concat(child.findAll(name));
		}
		return out;
	}

	/**
		Attaches a new component created from [className].

		The component document is appended with a fresh file id and wired into
		`m_Component`; return it to fill in the component specific fields.
	**/
	public function addComponent(className:String):Component
	{
		var classId = ClassIds.id(className);
		if (classId < 0) throw 'unknown Unity class name "$className"';
		return addComponentOfClass(classId);
	}

	/** Attaches a new component of [classId], see [addComponent]. **/
	public function addComponentOfClass(classId:Int, ?fileId:haxe.Int64):Component
	{
		var id = fileId == null ? prefab.documents.newFileId() : fileId;
		var fields = new YamlMap();
		fields.set("m_ObjectHideFlags", new YamlScalar("0", ScalarKind.Plain));
		fields.set("m_CorrespondingSourceObject", UnityReference.none().toNode());
		fields.set("m_PrefabInstance", UnityReference.none().toNode());
		fields.set("m_PrefabAsset", UnityReference.none().toNode());
		fields.set("m_GameObject", UnityReference.local(this.fileId()).toNode());
		if (ClassIds.isBehaviour(classId))
		{
			fields.set("m_Enabled", new YamlScalar("1", ScalarKind.Plain));
		}
		var document = new UnityYamlDocument(classId, id, false, wrap(ClassIds.name(classId), fields), 0);
		prefab.documents.add(document);
		var list = componentReferences();
		if (list != null)
		{
			var entry = new YamlMap();
			entry.set("component", UnityReference.local(id).toNode());
			// Unity lists the Transform first, so insert new components after it
			// rather than at the end, which keeps a written prefab looking native.
			var transform = this.transform();
			if (transform != null && list.length() > 0)
			{
				list.items.insert(1, entry);
			}
			else
			{
				list.push(entry);
			}
		}
		prefab.reindex();
		return Component.create(document, prefab);
	}

	/** Wraps [fields] in the single class-name key a Unity document body has. **/
	static function wrap(className:String, fields:YamlMap):YamlMap
	{
		var body = new YamlMap();
		body.set(className, fields);
		return body;
	}

	/**
		Adds a new child GameObject named [name].

		The child gets a `Transform` already parented to this object, so the
		hierarchy stays consistent.
	**/
	public function addChild(name:String):GameObjectObject
	{
		return prefab.createGameObject(name, this);
	}

	/** Moves this object under [newParent], or to the root when it is `null`. **/
	public function setParent(newParent:GameObjectObject):Void
	{
		var transform = this.transform();
		if (transform == null) return;
		transform.setParent(newParent);
	}

	/**
		Detaches this object and its descendants from the file.

		The GameObject document, its transform and every component document are
		removed, and the object is unlinked from its parent's `m_Children`. A scene
		root is also struck from `SceneRoots.m_Roots`, so a scene does not keep
		pointing at an object that no longer exists.
	**/
	public function remove():Void
	{
		var transform = this.transform();
		if (transform != null) transform.detachFromParent();
		var objects = descendants();
		objects.push(this);
		// Every transform goes, so every one is struck from `SceneRoots.m_Roots`
		// too. A prefab has no such document and this is a no-op there.
		for (object in objects)
		{
			var ownTransform = object.transform();
			if (ownTransform != null) prefab.unregisterSceneRoots(ownTransform.fileId());
		}
		for (object in objects)
		{
			object.removeDocuments();
		}
		prefab.reindex();
	}

	function removeDocuments():Void
	{
		for (component in components())
		{
			prefab.removeDocument(component.document);
		}
		prefab.removeDocument(document);
	}

	override public function toString():String
	{
		return 'GameObject("${name()}" ${hxunity.unity.FileId.toStr(fileId())})';
	}
}
