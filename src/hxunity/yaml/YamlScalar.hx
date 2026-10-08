package hxunity.yaml;

import haxe.Int64;

/** A YAML scalar that remembers how it was quoted. **/
class YamlScalar extends YamlNode
{
	/** Scalar text as written, without quotes and without the block header. **/
	public var raw(default, null):String;

	/** How the scalar was quoted in the source. **/
	public var kind(default, null):ScalarKind;

	/**
		The exact source spelling of a quoted or folded plain scalar, with line
		endings normalised to `\n`; `null` for other plain, block, synthetic and
		modified scalars. The writer replays it verbatim so escape case and fold
		breaks survive a round trip, and clears it on [setRaw].
	**/
	public var verbatim(default, null):String;

	/**
		True (default) when an empty plain value was written as `key: ` with a
		trailing space. Unity's importer meta files write `userData:` without it
		and its scene writer writes `value: ` with it; the writer keeps whichever
		the source had.
	**/
	public var spaceAfterColon(default, null):Bool;

	/** Explicit tag written before the value, e.g. `!u!114`, or `null`. **/
	public var tag(default, null):String;

	/** Anchor name declared after the value, or `null`. **/
	public var anchor(default, null):String;

	public function new(raw:String, kind:ScalarKind = Plain, line:Int = 0, column:Int = -1, tag:String = null, anchor:String = null, verbatim:String = null,
			spaceAfterColon:Bool = true)
	{
		super(line, column);
		this.raw = raw == null ? "" : raw;
		this.kind = cast kind;
		this.verbatim = verbatim;
		this.spaceAfterColon = spaceAfterColon;
		this.tag = tag;
		this.anchor = anchor;
	}

	/** Replaces the text while keeping the quoting style. **/
	public function setRaw(raw:String):Void
	{
		this.raw = raw == null ? "" : raw;
		this.verbatim = null;
		this.spaceAfterColon = true;
	}

	override public function asScalar():YamlScalar
	{
		return this;
	}

	/** Throws: a scalar is not a mapping, and a positioned error says where. **/
	override public function asMap():YamlMap
	{
		throw new YamlError("expected a mapping but found a scalar", line, column);
	}

	/** Throws: a scalar is not a sequence, and a positioned error says where. **/
	override public function asSeq():YamlSeq
	{
		throw new YamlError("expected a sequence but found a scalar", line, column);
	}

	override public function deepClone():YamlNode
	{
		return new YamlScalar(raw, kind, line, column, tag, anchor, verbatim, spaceAfterColon);
	}

	override public function isNull():Bool
	{
		return isPlain() && Scalars.isNullText(raw);
	}

	override public function toString():String
	{
		return raw;
	}

	override public function typeName():String
	{
		return "scalar";
	}

	/** True when the source did not quote the scalar. **/
	public function isPlain():Bool
	{
		return kind == Plain;
	}

	/** True when the source quoted the scalar, so it is definitely a string. **/
	public function isQuoted():Bool
	{
		return kind == SingleQuoted || kind == DoubleQuoted;
	}

	/** Scalar interpreted as a bool using YAML 1.1 rules. **/
	public function toBool():Bool
	{
		return Scalars.toBool(raw);
	}

	/** Scalar interpreted as a 32 bit int, or throws when it does not fit. **/
	public function toInt():Int
	{
		var v = Scalars.tryInt(raw);
		if (v == null) throw new YamlError('"$raw" is not a 32 bit integer', line, column);
		return v;
	}

	/** Scalar interpreted as a float, or throws when it is not numeric. **/
	public function toFloat():Float
	{
		var v = Scalars.tryFloat(raw);
		if (v == null) throw new YamlError('"$raw" is not a number', line, column);
		return v;
	}

	/**
		Scalar interpreted as a 64 bit integer.

		Unity file ids use the full signed 64 bit range, which [toInt] cannot
		represent. Use this, or [hxunity.unity.FileId], for anything that may be a
		`fileID`.
	**/
	public function toInt64():Int64
	{
		var v = Scalars.tryInt64(raw);
		if (v == null) throw new YamlError('"$raw" is not an integer', line, column);
		return v;
	}

	override public function deepEquals(other:YamlNode):Bool
	{
		if (!Std.isOfType(other, YamlScalar)) return false;
		var o:YamlScalar = cast other;
		return o.raw == raw && o.kind == kind && o.tag == tag;
	}

	override public function toHaxe():Dynamic
	{
		if (isQuoted() || kind == Literal || kind == Folded) return raw;
		return Scalars.toHaxe(raw);
	}

	override function writeJson(sb:StringBuf, indent:Int):Void
	{
		YamlWriter.writeJsonString(sb, raw);
	}
}
