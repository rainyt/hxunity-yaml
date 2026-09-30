package hxunity.prefab;

import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.ScalarKind;
import hxunity.types.QuaternionData;
import hxunity.types.VectorData;
import hxunity.unity.FileId;
import hxunity.unity.UnityReference;

/**
	A `Transform` or `RectTransform`, and with it the prefab's hierarchy.

	Unity stores the hierarchy on the transforms: `m_Father` points at the parent
	transform and `m_Children` lists the child transforms. [setParent] and
	[detachFromParent] keep both ends of every link consistent, which is the part
	that is easy to get wrong by hand.
**/
class TransformObject extends Component {
	public function new(document:UnityYamlDocument, prefab:UnityPrefab) {
		super(document, prefab);
	}

	/** The GameObject this transform belongs to. **/
	override public function gameObject():GameObjectObject {
		return super.gameObject();
	}

	/** `m_LocalPosition`, or `null`. **/
	public function localPosition():VectorData {
		return VectorData.fromField(fields(), "m_LocalPosition");
	}

	/** Sets `m_LocalPosition`. **/
	public function setLocalPosition(value:VectorData):Void {
		value.writeTo(fields(), "m_LocalPosition");
	}

	/** `m_LocalScale`, or `null`. **/
	public function localScale():VectorData {
		return VectorData.fromField(fields(), "m_LocalScale");
	}

	/** Sets `m_LocalScale`. **/
	public function setLocalScale(value:VectorData):Void {
		value.writeTo(fields(), "m_LocalScale");
	}

	/** `m_LocalRotation`, or `null`. **/
	public function localRotation():QuaternionData {
		return QuaternionData.fromField(fields(), "m_LocalRotation");
	}

	/** Sets `m_LocalRotation`. **/
	public function setLocalRotation(value:QuaternionData):Void {
		fields().set("m_LocalRotation", value.toNode());
	}

	/**
		`m_LocalEulerAnglesHint`, or `null`.

		This is an editor hint only: Unity recomputes the real rotation from
		`m_LocalRotation`, and the hint exists so the inspector can show stable
		euler angles.
	**/
	public function localEulerAnglesHint():VectorData {
		return VectorData.fromField(fields(), "m_LocalEulerAnglesHint");
	}

	/** Sets `m_LocalEulerAnglesHint`. **/
	public function setLocalEulerAnglesHint(value:VectorData):Void {
		value.writeTo(fields(), "m_LocalEulerAnglesHint");
	}

	/**
		Parent transform, or `null` when this is a root transform.

		A non-null result is not on its own proof that this object sits in the
		hierarchy: `m_Father` may name a **stripped** transform, which is what Unity
		writes for the parent side of a prefab instance. Such a document exists and
		is indexed, but carries no `m_GameObject` (its owner lives in the source
		prefab), so the wrapper is real while [gameObject] on it is `null`. Use
		[parent] when the question is "does this object have a parent in this
		file?" — that is what [parent] answers, and it is `null` in this case.
	**/
	public function parentTransform():TransformObject {
		var reference = getReference("m_Father");
		if (reference == null || reference.isExternal())
			return null;
		var document = prefab.documents.byId(reference.fileId);
		// `m_Father` is a transform reference, but a malformed or hand edited file
		// can point it at anything, so the resolved document is type checked before
		// it is wrapped as a TransformObject.
		if (!isTransformDocument(document))
			return null;
		return new TransformObject(document, prefab);
	}

	/** True when [document] is a Transform or RectTransform that resolves here. **/
	static function isTransformDocument(document:UnityYamlDocument):Bool {
		if (document == null)
			return false;
		return document.classId == ClassIds.Transform || document.classId == ClassIds.RectTransform;
	}

	/**
		Parent GameObject, or `null` for a root object.

		`null` covers both a root transform (`m_Father: {fileID: 0}`) and a transform
		whose `m_Father` names an object that has no GameObject in this file, such as
		a stripped prefab-instance parent. That keeps an object from dropping out of
		both the parent list and the root list.
	**/
	public function parent():GameObjectObject {
		var owner = parentTransform();
		return owner == null ? null : owner.gameObject();
	}

	/** `m_Children` as transform wrappers, in serialised order. **/
	public function childTransforms():Array<TransformObject> {
		var out = [];
		var list = getSeq("m_Children");
		if (list == null)
			return out;
		for (item in list.items) {
			var reference = UnityReference.fromNode(item);
			if (reference == null || reference.isExternal())
				continue;
			var document = prefab.documents.byId(reference.fileId);
			// Skip anything that is not a transform document for the same reason
			// parentTransform type checks: a wrong fileID must not be wrapped.
			if (isTransformDocument(document))
				out.push(new TransformObject(document, prefab));
		}
		return out;
	}

	/** Direct children GameObjects, in `m_Children` order. **/
	public function children():Array<GameObjectObject> {
		var out = [];
		for (child in childTransforms()) {
			var owner = child.gameObject();
			if (owner != null)
				out.push(owner);
		}
		return out;
	}

	/** Index of this transform in its parent's `m_Children`, or -1 at the root. **/
	public function siblingIndex():Int {
		var parentTransform = this.parentTransform();
		if (parentTransform == null)
			return -1;
		var list = parentTransform.getSeq("m_Children");
		if (list == null)
			return -1;
		for (i in 0...list.items.length) {
			var reference = UnityReference.fromNode(list.items[i]);
			if (reference != null && FileId.compare(reference.fileId, fileId()) == 0)
				return i;
		}
		return -1;
	}

	/**
		Moves this transform under [newParent], or to the root when it is `null`.

		Both links are updated: `m_Father` here and `m_Children` on the old and new
		parent. The local position and scale are left untouched, which matches
		Unity's `SetParent(parent, false)`.
	**/
	public function setParent(newParent:GameObjectObject):Void {
		var target = newParent == null ? null : newParent.transform();
		if (target != null && FileId.compare(target.fileId(), fileId()) == 0)
			return;
		detachFromParent();
		set("m_Father", target == null ? UnityReference.none().toNode() : UnityReference.local(target.fileId()).toNode());
		if (target != null) {
			var list = target.getSeq("m_Children");
			if (list == null) {
				list = new YamlSeq();
				target.set("m_Children", list);
			}
			list.push(UnityReference.local(fileId()).toNode());
		}
	}

	/** Removes this transform from its parent's `m_Children` and clears `m_Father`. **/
	public function detachFromParent():Void {
		var parentTransform = this.parentTransform();
		if (parentTransform != null) {
			var list = parentTransform.getSeq("m_Children");
			if (list != null) {
				var index = list.items.length - 1;
				while (index >= 0) {
					var reference = UnityReference.fromNode(list.items[index]);
					if (reference != null && FileId.compare(reference.fileId, fileId()) == 0) {
						list.removeAt(index);
						break;
					}
					index--;
				}
			}
		}
		set("m_Father", UnityReference.none().toNode());
	}

	/**
		Moves this transform to [index] among its parent's children.

		The `m_Children` order is what Unity uses for draw order and for the
		inspector's sibling list, so reordering matters for rendering.
	**/
	public function setSiblingIndex(index:Int):Void {
		var parentTransform = this.parentTransform();
		if (parentTransform == null)
			return;
		var list = parentTransform.getSeq("m_Children");
		if (list == null)
			return;
		var current = siblingIndex();
		if (current < 0)
			return;
		var reference = list.items[current];
		list.removeAt(current);
		var target = index < 0 ? 0 : (index > list.items.length ? list.items.length : index);
		list.items.insert(target, reference);
	}

	override public function toString():String {
		var owner = gameObject();
		return 'Transform("${owner == null ? "?" : owner.name()}" ${FileId.toStr(fileId())})';
	}
}
