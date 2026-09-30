package hxunity.yaml;

/**
	Kind of a scalar as it appeared in the source document.

	The kind is recorded instead of being thrown away because Unity writes
	`type: 2` (an int) and `value: 2` (also an int) but distinguishes them from
	strings only through quoting. Round tripping a prefab byte for byte depends
	on remembering which scalars were quoted.
**/
enum abstract ScalarKind(String) from String to String
{
	/** Unquoted scalar, e.g. `m_Name: alex_fat` or `- 3`. **/
	var Plain = "plain";

	/** Single quoted scalar, e.g. `_serializedGraph: '{"type":"..."}'`. **/
	var SingleQuoted = "single";

	/** Double quoted scalar with escape sequences. **/
	var DoubleQuoted = "double";

	/** Literal block scalar, `key: |` and friends. **/
	var Literal = "literal";

	/** Folded block scalar, `key: >` and friends. **/
	var Folded = "folded";
}
