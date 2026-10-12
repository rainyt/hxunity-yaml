package hxunity.prefab;

import haxe.Int64;
import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlParseOptions;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlWriteOptions;
import hxunity.unity.ComponentDefaults;
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
	var transforms:Map<String, TransformObject>;

	public function new(documents:UnityDocumentSet, ?path:String, ?parseOptions:YamlParseOptions, ?writeOptions:YamlWriteOptions)
	{
		this.documents = documents;
		this.path = path;
		this.parseOptions = parseOptions;
		this.writeOptions = writeOptions;
		this.gameObjects = new Map();
		this.components = new Map();
		this.transforms = new Map();
	}

	/** Parses prefab text. **/
	public static function parse(text:String, ?options:YamlParseOptions):UnityPrefab
	{
		return new UnityPrefab(UnityDocumentSet.parse(text, options), null, options);
	}

	/**
		Independent deep copy of the whole object graph.

		Unlike a parse round trip this does not serialise and re-read the file —
		it clones the node trees directly, which is an order of magnitude cheaper
		on large prefabs. The clone's [path] is `null`, so calling [save] without
		an explicit path throws instead of overwriting the source file.
	**/
	public function deepClone():UnityPrefab
	{
		return new UnityPrefab(documents.clone(), null, parseOptions, writeOptions);
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
		return new UnityPrefab(UnityDocumentSet.createEmpty());
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
		transforms.clear();
	}

	/** Wrapped `GameObject` for [fileId], or `null`. **/
	public function gameObjectById(fileId:Int64):GameObjectObject
	{
		return fileId == null ? null : gameObjectByIdText(Int64.toStr(fileId));
	}

	/**
		Wrapped `GameObject` for an id given as decimal text, or `null`.

		The text is the id's original spelling, so a caller that already holds one
		— an id read from a `{fileID: ...}` reference, or
		[UnityYamlDocument.fileIdText] — never pays `Int64.toStr`'s software
		division. This is the form to reach for inside the library; the [Int64]
		overload exists for callers that only ever had a parsed id.
	**/
	public function gameObjectByIdText(fileIdText:String):GameObjectObject
	{
		if (fileIdText == null) return null;
		var cached = gameObjects.get(fileIdText);
		if (cached != null) return cached;
		var document = documents.byIdText(fileIdText);
		if (document == null || document.classId != ClassIds.GameObject) return null;
		var created = new GameObjectObject(document, this);
		gameObjects.set(fileIdText, created);
		return created;
	}

	/** Wrapped component for [fileId], or `null` when it is not a component. **/
	public function componentById(fileId:Int64):Component
	{
		return fileId == null ? null : componentByIdText(Int64.toStr(fileId));
	}

	/** Wrapped component for an id given as decimal text, see [gameObjectByIdText]. **/
	public function componentByIdText(fileIdText:String):Component
	{
		if (fileIdText == null) return null;
		var cached = components.get(fileIdText);
		if (cached != null) return cached;
		var document = documents.byIdText(fileIdText);
		if (document == null || !ClassIds.isComponent(document.classId)) return null;
		var created = Component.create(document, this);
		components.set(fileIdText, created);
		return created;
	}

	/**
		Wrapped [GameObject] for an already-resolved document.

		Hierarchy traversal resolves references to documents and then wraps them;
		doing that through [gameObjectById] would pay `Int64.toStr` (Haxe's
		software 64-bit division, the top CPU cost on JavaScript) and allocate a
		fresh wrapper on every call. This path keys on the document's memoised
		id text and caches the wrapper.
	**/
	public function gameObjectByDocument(document:UnityYamlDocument):GameObjectObject
	{
		if (document == null || document.classId != ClassIds.GameObject) return null;
		var key = document.fileIdText();
		var cached = gameObjects.get(key);
		if (cached != null) return cached;
		var created = new GameObjectObject(document, this);
		gameObjects.set(key, created);
		return created;
	}

	/**
		Cached [TransformObject] wrapper for an already-resolved transform document.

		Hierarchy traversal creates one wrapper per child per pass; without this
		cache every `children()` call allocates the whole subtree's wrappers again
		and feeds the generational GC (the top cost on the JavaScript target).
	**/
	public function transformByDocument(document:UnityYamlDocument):TransformObject
	{
		if (document == null) return null;
		if (document.classId != ClassIds.Transform && document.classId != ClassIds.RectTransform) return null;
		var key = document.fileIdText();
		var cached = transforms.get(key);
		if (cached != null) return cached;
		var created = new TransformObject(document, this);
		transforms.set(key, created);
		return created;
	}

	/** Cached component wrapper for an already-resolved document, see [gameObjectByDocument]. **/
	public function componentByDocument(document:UnityYamlDocument):Component
	{
		if (document == null || !ClassIds.isComponent(document.classId)) return null;
		var key = document.fileIdText();
		var cached = components.get(key);
		if (cached != null) return cached;
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
				var object = gameObjectByDocument(document);
				if (object != null) out.push(object);
			}
		}
		return out;
	}

	/**
		Root GameObjects: those whose transform has no parent.

		A prefab normally has exactly one; a scene has one per root object, and a
		`.asset` has none.

		"Has no parent" is decided through [TransformObject.parent] rather than by
		testing `parentTransform() == null`, because `m_Father` can name a stripped
		prefab-instance transform: that document is resolvable, but it has no
		GameObject in this file. Treating such an object as parented would drop it
		out of the roots as well, leaving it reachable only by [allGameObjects].
	**/
	public function rootGameObjects():Array<GameObjectObject>
	{
		var out = [];
		for (object in allGameObjects())
		{
			var transform = object.transform();
			if (transform == null) continue;
			if (transform.parent() == null) out.push(object);
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
				var component = componentByDocument(document);
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
		`m_Children`. The field sets come from
		[hxunity.unity.ComponentDefaults], which is where they are kept in one
		place and compared against real Unity output.

		[rectTransform] creates a `RectTransform` instead of a `Transform`, which
		is what a UI hierarchy needs. It has to be decided here rather than by a
		later `addComponent("RectTransform")`: Unity allows one transform per
		GameObject, so a second one is never a valid edit.
	**/
	public function createGameObject(name:String, ?parent:GameObjectObject, ?fileId:Int64, rectTransform:Bool = false):GameObjectObject
	{
		var gameObjectId = fileId == null ? documents.newFileId() : fileId;
		var transformId = documents.newFileId();
		var transformClass = rectTransform ? ClassIds.RectTransform : ClassIds.Transform;

		var fields = ComponentDefaults.gameObject(name, transformId);
		var gameObjectDocument = new UnityYamlDocument(ClassIds.GameObject, gameObjectId, false,
			wrap(ClassIds.name(ClassIds.GameObject), fields), 0, true, true);

		var parentTransform = parent == null ? null : parent.transform();
		var transformFields = ComponentDefaults.transform(gameObjectId, parentTransform == null ? null : parentTransform.fileId(), rectTransform);

		var transformDocument = new UnityYamlDocument(transformClass, transformId, false,
			wrap(ClassIds.name(transformClass), transformFields), 0, true, true);

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
		gameObjects.set(gameObjectDocument.fileIdText(), object);
		registerSceneRoots(transformId, parent == null);
		return object;
	}

	/**
		Adds the transform [transformFileId] to the `SceneRoots` list.

		`m_Roots` holds **transform** file ids, not GameObject ids, which is why this
		takes an id rather than a document. Only a scene has a `SceneRoots` document
		(class id 1660057539), and only root objects belong in its `m_Roots`, so this
		is a no-op for a prefab and for an object created under a parent.
	**/
	function registerSceneRoots(transformFileId:Int64, isRoot:Bool):Void
	{
		if (!isRoot || transformFileId == null) return;
		var sceneRoots = documents.firstOfClass(ClassIds.SceneRoots);
		if (sceneRoots == null) return;
		// The document body is `SceneRoots:` wrapping the fields, so the list has
		// to be read through the class-name key rather than off the body itself.
		var fields = sceneRoots.getMap(sceneRoots.bodyName);
		if (fields == null) return;
		var roots = fields.getSeq("m_Roots");
		if (roots == null)
		{
			roots = new YamlSeq();
			fields.set("m_Roots", roots);
		}
		roots.push(UnityReference.local(transformFileId).toNode());
	}

	/** Wraps [fields] in the single class-name key a Unity document body has. **/
	static function wrap(className:String, fields:YamlMap):YamlMap
	{
		var body = new YamlMap();
		body.set(className, fields);
		return body;
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
		gameObjects.remove(document.fileIdText());
		components.remove(document.fileIdText());
	}

	/** Appends [document] or replaces the document with the same file id. **/
	public function addDocument(document:UnityYamlDocument):UnityYamlDocument
	{
		if (documents.containsText(document.fileIdText()))
		{
			documents.replace(document);
		}
		else
		{
			documents.add(document);
		}
		gameObjects.remove(document.fileIdText());
		components.remove(document.fileIdText());
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
			var key = document.fileIdText();
			if (idMap.exists(key)) continue;
			idMap.set(key, documents.newFileId());
			byId.set(key, document);
		}

		// Copy each subtree document and rewrite the references that point back
		// into the subtree.
		var copies = new Map<String, UnityYamlDocument>();
		for (document in originals)
		{
			var key = document.fileIdText();
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
			var key = document.fileIdText();
			var copy = copies.get(key);
			if (copy == null) continue;
			var at = documents.documents.indexOf(document) + 1;
			if (at > documents.documents.length) at = documents.documents.length;
			documents.insert(at, copy);
		}

		documents.reindex();
		// The id looked up here was minted by [UnityDocumentSet.newFileId], so it
		// has no original spelling to reuse: this one `Int64.toStr` is unavoidable.
		var clone = gameObjectById(idMap.get(source.document.fileIdText()));
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

	/**
		Removes the entry for a transform from the `SceneRoots` list.

		The counterpart of [registerSceneRoots]: a scene root that is deleted has to
		disappear from `m_Roots` as well, or Unity treats the scene as referencing a
		missing object. A no-op for a prefab, and for a transform that is not listed.
		[GameObjectObject.remove] calls this, so deleting a root keeps the scene
		consistent without the caller doing anything.
	**/
	public function unregisterSceneRoots(transformFileId:Int64):Void
	{
		if (transformFileId == null) return;
		var sceneRoots = documents.firstOfClass(ClassIds.SceneRoots);
		if (sceneRoots == null) return;
		var fields = sceneRoots.getMap(sceneRoots.bodyName);
		if (fields == null) return;
		var roots = fields.getSeq("m_Roots");
		if (roots == null) return;
		var index = roots.items.length - 1;
		while (index >= 0)
		{
			var reference = UnityReference.fromNode(roots.items[index]);
			if (reference != null && FileId.compare(reference.fileId, transformFileId) == 0)
			{
				roots.removeAt(index);
			}
			index--;
		}
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
		return new YamlScalar(scalar.raw, scalar.kind, scalar.line, scalar.column, scalar.tag, scalar.anchor, scalar.verbatim);
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
