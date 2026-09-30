package hxunity.prefab;

import haxe.Int64;
import hxunity.yaml.ClassIds;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlParseOptions;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlWriteOptions;
import hxunity.unity.FileId;
import hxunity.unity.UnityReference;
import hxunity.yaml.YamlNode;

/**
	High level reader/writer for a Unity 2022.3 prefab (or any other Unity YAML
	asset): `.prefab`, `.asset`, `.unity`, `.mat`, `.controller`, `.meta`.

	The class keeps the parsed [UnityDocumentSet] and adds an object graph on top,
	so the hierarchy can be walked by name instead of by `fileID`:

	```haxe
	var prefab = UnityPrefab.fromFile("Assets/Hero.prefab");
	var root = prefab.rootGameObjects()[0];
	for (child in root.children())
	{
		if (child.name() == "Hand")
		{
			var transform = child.transform();
			transform.setLocalPosition(new VectorData(0.5, 1, 0));
		}
	}
	prefab.save();
	```

	Editing is in place: every mutator writes through to the underlying YAML
	nodes, so [save] emits the file with the original field order, quoting and
	formatting preserved except where the caller changed something.
**/
class UnityPrefab
{
	/** Parsed documents, in file order. **/
	public var documents(default, null):UnityDocumentSet;

	/** Path the prefab was loaded from, or `null` when it was parsed from text. **/
	public var path(default, null):String;

	/** Parse options applied when loading. **/
	public var parseOptions(default, null):YamlParseOptions;

	/** Write options applied when saving. **/
	public var writeOptions(default, null):YamlWriteOptions;

	var gameObjects:Map<String, GameObjectObject>;
	var components:Map<String, Component>;

	public function new(documents:UnityDocumentSet, ?path:String, ?parseOptions:YamlParseOptions, ?writeOptions:YamlWriteOptions)
	{
		this.documents = documents;
		this.path = path;
		this.parseOptions = parseOptions;
		this.writeOptions = writeOptions;
		this.gameObjects = new Map();
		this.components = new Map();
	}

	/** Parses prefab text. **/
	public static function parse(text:String, ?options:YamlParseOptions):UnityPrefab
	{
		return new UnityPrefab(UnityDocumentSet.parse(text, options), null, options);
	}

	/** Reads and parses a file from disk. **/
	public static function fromFile(path:String, ?options:YamlParseOptions):UnityPrefab
	{
		var text = sys.io.File.getContent(path);
		return new UnityPrefab(UnityDocumentSet.parse(text, options), path, options);
	}

	/** An empty prefab with the standard `%YAML` / `%TAG` preamble. **/
	public static function createEmpty():UnityPrefab
	{
		var set = new UnityDocumentSet(["%YAML 1.1", "%TAG !u! tag:unity3d.com,2011:"], [], "\n", true);
		return new UnityPrefab(set);
	}

	// ------------------------------------------------------------------- lookup

	/**
		Rebuilds the id index and drops the wrapper caches.

		Called after structural edits; it is cheap, so [createGameObject] and
		[duplicate] call it themselves.
	**/
	public function reindex():Void
	{
		documents.reindex();
		gameObjects.clear();
		components.clear();
	}

	/** Wrapped `GameObject` for [fileId], or `null`. **/
	public function gameObjectById(fileId:Int64):GameObjectObject
	{
		if (fileId == null) return null;
		var key = Int64.toStr(fileId);
		var cached = gameObjects.get(key);
		if (cached != null) return cached;
		var document = documents.byId(fileId);
		if (document == null || document.classId != ClassIds.GameObject) return null;
		var created = new GameObjectObject(document, this);
		gameObjects.set(key, created);
		return created;
	}

	/** Wrapped component for [fileId], or `null` when it is not a component. **/
	public function componentById(fileId:Int64):Component
	{
		if (fileId == null) return null;
		var key = Int64.toStr(fileId);
		var cached = components.get(key);
		if (cached != null) return cached;
		var document = documents.byId(fileId);
		if (document == null || !ClassIds.isComponent(document.classId)) return null;
		var created = Component.create(document, this);
		components.set(key, created);
		return created;
	}

	/** Every GameObject in the file, in document order. **/
	public function allGameObjects():Array<GameObjectObject>
	{
		var out = [];
		for (document in documents.documents)
		{
			if (document.classId == ClassIds.GameObject)
			{
				var object = gameObjectById(document.fileId);
				if (object != null) out.push(object);
			}
		}
		return out;
	}

	/**
		Root GameObjects: those whose transform has no parent.

		A prefab normally has exactly one; a scene has one per root object, and a
		`.asset` has none.
	**/
	public function rootGameObjects():Array<GameObjectObject>
	{
		var out = [];
		for (object in allGameObjects())
		{
			var transform = object.transform();
			if (transform == null) continue;
			if (transform.parentTransform() == null) out.push(object);
		}
		return out;
	}

	/** First GameObject named [name] anywhere in the file, or `null`. **/
	public function find(name:String):GameObjectObject
	{
		for (object in allGameObjects())
		{
			if (object.name() == name) return object;
		}
		return null;
	}

	/** First GameObject whose hierarchy path is [path], or `null`. **/
	public function findByPath(path:String):GameObjectObject
	{
		for (object in allGameObjects())
		{
			if (object.path() == path) return object;
		}
		return null;
	}

	/** Every GameObject named [name]. **/
	public function findAll(name:String):Array<GameObjectObject>
	{
		var out = [];
		for (object in allGameObjects())
		{
			if (object.name() == name) out.push(object);
		}
		return out;
	}

	/** Every component of class [classId] in the file, in document order. **/
	public function allComponentsOfType(classId:Int):Array<Component>
	{
		var out = [];
		for (document in documents.documents)
		{
			if (document.classId == classId)
			{
				var component = componentById(document.fileId);
				if (component != null) out.push(component);
			}
		}
		return out;
	}

	/** The first document whose class id is [classId], or `null`. **/
	public function firstDocumentOfClass(classId:Int):UnityYamlDocument
	{
		return documents.firstOfClass(classId);
	}

	// ---------------------------------------------------------------- structure

	/**
		Creates a GameObject, optionally parented to [parent].

		The object is written the way Unity writes one: a `GameObject` document
		with `serializedVersion: 6` and a `Transform` with `serializedVersion: 2`,
		each linked to the other, and the transform registered in the parent's
		`m_Children`.
	**/
	public function createGameObject(name:String, ?parent:GameObjectObject, ?fileId:Int64):GameObjectObject
	{
		var gameObjectId = fileId == null ? documents.newFileId() : fileId;
		var transformId = documents.newFileId();

		var fields = new YamlMap();
		fields.set("m_ObjectHideFlags", plain("0"));
		fields.set("m_CorrespondingSourceObject", UnityReference.none().toNode());
		fields.set("m_PrefabInstance", UnityReference.none().toNode());
		fields.set("m_PrefabAsset", UnityReference.none().toNode());
		fields.set("serializedVersion", plain("6"));
		var componentList = new YamlSeq();
		var transformEntry = new YamlMap();
		transformEntry.set("component", UnityReference.local(transformId).toNode());
		componentList.push(transformEntry);
		fields.set("m_Component", componentList);
		fields.set("m_Layer", plain("0"));
		fields.set("m_Name", plain(name));
		fields.set("m_TagString", plain("Untagged"));
		fields.set("m_Icon", UnityReference.none().toNode());
		fields.set("m_NavMeshLayer", plain("0"));
		fields.set("m_StaticEditorFlags", plain("0"));
		fields.set("m_IsActive", plain("1"));

		var gameObjectDocument = new UnityYamlDocument(ClassIds.GameObject, gameObjectId, false,
			wrap(ClassIds.name(ClassIds.GameObject), fields), 0, true, true);

		var parentTransform = parent == null ? null : parent.transform();
		var transformFields = new YamlMap();
		transformFields.set("m_ObjectHideFlags", plain("0"));
		transformFields.set("m_CorrespondingSourceObject", UnityReference.none().toNode());
		transformFields.set("m_PrefabInstance", UnityReference.none().toNode());
		transformFields.set("m_PrefabAsset", UnityReference.none().toNode());
		transformFields.set("m_GameObject", UnityReference.local(gameObjectId).toNode());
		transformFields.set("serializedVersion", plain("2"));
		transformFields.set("m_LocalRotation", identityRotation());
		transformFields.set("m_LocalPosition", new hxunity.types.VectorData(0, 0, 0).toNode());
		transformFields.set("m_LocalScale", new hxunity.types.VectorData(1, 1, 1).toNode());
		transformFields.set("m_ConstrainProportionsScale", plain("0"));
		transformFields.set("m_Children", new YamlSeq());
		transformFields.set("m_Father",
			parentTransform == null ? UnityReference.none().toNode() : UnityReference.local(parentTransform.fileId()).toNode());
		transformFields.set("m_LocalEulerAnglesHint", new hxunity.types.VectorData(0, 0, 0).toNode());

		var transformDocument = new UnityYamlDocument(ClassIds.Transform, transformId, false,
			wrap(ClassIds.name(ClassIds.Transform), transformFields), 0, true, true);

		documents.add(gameObjectDocument);
		documents.add(transformDocument);

		if (parentTransform != null)
		{
			var children = parentTransform.getSeq("m_Children");
			if (children == null)
			{
				children = new YamlSeq();
				parentTransform.set("m_Children", children);
			}
			children.push(UnityReference.local(transformId).toNode());
		}

		var object = new GameObjectObject(gameObjectDocument, this);
		gameObjects.set(Int64.toStr(gameObjectId), object);
		registerSceneRoots(gameObjectDocument);
		return object;
	}

	/** Replaces the `SceneRoots` list of a `.unity` file with [document]. **/
	function registerSceneRoots(gameObjectDocument:UnityYamlDocument):Void
	{
		var sceneRoots = documents.firstOfClass(ClassIds.SceneRoots);
		if (sceneRoots == null) return;
		var fields = sceneRoots.get("m_Roots");
		if (fields == null || !Std.isOfType(fields, YamlSeq)) return;
		var roots:YamlSeq = cast fields;
		roots.push(UnityReference.local(gameObjectDocument.fileId).toNode());
	}

	static function identityRotation():YamlMap
	{
		return new hxunity.types.QuaternionData(0, 0, 0, 1).toNode();
	}

	/** Wraps [fields] in the single class-name key a Unity document body has. **/
	static function wrap(className:String, fields:YamlMap):YamlMap
	{
		var body = new YamlMap();
		body.set(className, fields);
		return body;
	}

	static function plain(text:String):YamlScalar
	{
		return new YamlScalar(text, ScalarKind.Plain);
	}

	// ------------------------------------------------------------------ editing

	/** Removes a wrapped object's document and forgets it. **/
	public function removeObject(object:UnityObject):Void
	{
		removeDocument(object.document);
	}

	/** Removes a document by identity and forgets any cached wrapper. **/
	public function removeDocument(document:UnityYamlDocument):Void
	{
		documents.remove(document);
		gameObjects.remove(Int64.toStr(document.fileId));
		components.remove(Int64.toStr(document.fileId));
	}

	/** Appends [document] or replaces the document with the same file id. **/
	public function addDocument(document:UnityYamlDocument):UnityYamlDocument
	{
		if (documents.contains(document.fileId))
		{
			documents.replace(document);
		}
		else
		{
			documents.add(document);
		}
		gameObjects.remove(Int64.toStr(document.fileId));
		components.remove(Int64.toStr(document.fileId));
		documents.reindex();
		return document;
	}

	/** Position of [document] in the file, or -1. **/
	public function indexOfDocument(document:UnityYamlDocument):Int
	{
		return documents.documents.indexOf(document);
	}

	/**
		Deep copies [source] and its whole subtree under [newParent].

		Every document of the subtree gets a fresh file id, and references *within*
		the subtree are pointed at the copies. A reference that leaves the subtree —
		to the original parent, to a material, to a script — is deliberately
		rewritten as well when it points at one of the copied documents, and left
		alone otherwise. That is what makes a duplicated object keep using the same
		assets while no longer sharing its own internals with the original.
	**/
	public function duplicate(source:GameObjectObject, ?newParent:GameObjectObject):GameObjectObject
	{
		var parent = newParent == null ? source.parent() : newParent;
		var included = [source];
		included = included.concat(source.descendants());

		// Collect the documents that make up the subtree, in file order.
		var originals = [];
		for (object in included)
		{
			originals.push(object.document);
			var transform = object.transform();
			if (transform != null) originals.push(transform.document);
			for (component in object.components())
			{
				if (transform == null || component.fileId() != transform.fileId())
				{
					originals.push(component.document);
				}
			}
		}

		// Map each original subtree document to a fresh file id.
		var idMap = new Map<String, Int64>();
		var byId = new Map<String, UnityYamlDocument>();
		for (document in originals)
		{
			var key = Int64.toStr(document.fileId);
			if (idMap.exists(key)) continue;
			idMap.set(key, documents.newFileId());
			byId.set(key, document);
		}

		// Copy each subtree document and rewrite the references that point back
		// into the subtree.
		var copies = new Map<String, UnityYamlDocument>();
		for (document in originals)
		{
			var key = Int64.toStr(document.fileId);
			if (copies.exists(key)) continue;
			var copy = copyDocument(document, idMap.get(key));
			copies.set(key, copy);
		}
		for (key => copy in copies)
		{
			remapReferences(copy.body, idMap);
		}

		// Insert every copy directly after its original so the file keeps a
		// readable, Unity-like order.
		for (document in originals)
		{
			var key = Int64.toStr(document.fileId);
			var copy = copies.get(key);
			if (copy == null) continue;
			var at = documents.documents.indexOf(document) + 1;
			if (at > documents.documents.length) at = documents.documents.length;
			documents.insert(at, copy);
		}

		documents.reindex();
		var clone = gameObjectById(idMap.get(Int64.toStr(source.fileId())));
		if (clone != null)
		{
			// The copy's transform still points at the original's parent, but the
			// parent does not list the copy yet. Reparenting fixes both ends; a
			// clone of a root object needs no such fix, and `setParent(null)` would
			// clear the reference it already holds.
			if (parent != null)
			{
				clone.setParent(parent);
			}
		}
		return clone;
	}

	/** Copies a document's body, giving the copy [newId]. **/
	function copyDocument(document:UnityYamlDocument, newId:Int64):UnityYamlDocument
	{
		var body:YamlMap = cast cloneNode(document.body);
		var id = newId == null ? documents.newFileId() : newId;
		return new UnityYamlDocument(document.classId, id, document.stripped, body, 0, document.hasFileId, document.hasHeader);
	}

	/** Deep copies a node. **/
	function cloneNode(node:YamlNode):YamlNode
	{
		if (Std.isOfType(node, YamlMap))
		{
			var source:YamlMap = cast node;
			var copy = new YamlMap(null, source.flow, source.line, source.column);
			for (entry in source.entries)
			{
				copy.add(entry.key, cloneNode(entry.value));
			}
			return copy;
		}
		if (Std.isOfType(node, YamlSeq))
		{
			var source:YamlSeq = cast node;
			var copy = new YamlSeq(null, source.flow, source.line, source.column);
			for (item in source.items)
			{
				copy.push(cloneNode(item));
			}
			return copy;
		}
		var scalar:YamlScalar = cast node;
		return new YamlScalar(scalar.raw, scalar.kind, scalar.line, scalar.column, scalar.tag, scalar.anchor);
	}

	/**
		Rewrites every local `{fileID: N}` reference in [node] through [idMap].

		A reference is only remapped when the mapping contains the id, so a pointer
		to something outside the copied subtree is left untouched. References that
		carry a `guid` name another asset and never refer to a document in this
		file, so they are skipped.
	**/
	function remapReferences(node:YamlNode, idMap:Map<String, Int64>):Void
	{
		if (Std.isOfType(node, YamlMap))
		{
			var map:YamlMap = cast node;
			if (map.flow && map.has("fileID") && !map.has("guid"))
			{
				var mapped = idMap.get(map.getString("fileID"));
				if (mapped != null) map.setRaw("fileID", Int64.toStr(mapped));
			}
			for (entry in map.entries)
			{
				remapReferences(entry.value, idMap);
			}
			return;
		}
		if (Std.isOfType(node, YamlSeq))
		{
			var seq:YamlSeq = cast node;
			for (item in seq.items)
			{
				remapReferences(item, idMap);
			}
		}
	}

	// ------------------------------------------------------------------ writing

	/** Serialises the whole file back to Unity YAML text. **/
	public function emit(?options:YamlWriteOptions):String
	{
		return documents.emit(options == null ? writeOptions : options);
	}

	/**
		Writes the file back to [path], or to the path it was loaded from.

		The original line endings and preamble are preserved, so a file that was
		not modified is written back byte for byte.
	**/
	public function save(?path:String, ?options:YamlWriteOptions):Void
	{
		var target = path == null ? this.path : path;
		if (target == null) throw "UnityPrefab.save needs a path";
		sys.io.File.saveContent(target, emit(options));
	}

	/** Number of documents in the file. **/
	public function count():Int
	{
		return documents.count();
	}

	public function toString():String
	{
		return 'UnityPrefab(${path == null ? "<memory>" : path}, ${count()} documents)';
	}
}
