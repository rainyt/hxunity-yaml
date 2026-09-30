package;

/** Thrown by a failed assertion, carrying the test it belongs to. **/
class AssertionFailure
{
	/** Name of the test that was running. **/
	public var testName(default, null):String;

	/** Description of the expectation that was not met. **/
	public var detail(default, null):String;

	public function new(testName:String, detail:String)
	{
		this.testName = testName;
		this.detail = detail;
	}

	public function toString():String
	{
		return '[$testName] $detail';
	}
}
