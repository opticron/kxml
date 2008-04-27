/**
 * Copyright:  (c) 2005-2007 Eric Poggel
 * Authors:    Andy Friesen, Eric Poggel
 * License:    <a href="lgpl.txt">LGPL</a>
 *
 * Xml contains functions and classes for reading, parsing, and writing xml
 * documents.
 *
 * It might eventually be good to rewrite this to throw Exceptions on any parse
 * errors--it already catches some.
 *
 * History:
 * Most of the code in this module originally came from Andy Friesen's Xmld.
 * Xmld was unmaintained, but Andy had placed it in the public domain.  This
 * version has been modified to compile under recent versions of dmd and
 * consolidated into a single module.
 */

module KXML.xml;

import std.stream;
import std.string;
import std.regexp;
import std.stdio;

/**
 * Read an entire stream into a tree of XmlNodes.
 * Example:
 * --------------------------------
 * XmlNode xml;
 * File file = new File(source, FileMode.In);
 * xml = readDocument(file);
 * file.close();
 * --------------------------------*/
XmlNode readDocument(char[]src)
{
	XmlNode root = new XmlNode("");
	root.addChildren(src);
	return root;
}

/// An exception thrown on an xml parsing error.
class XmlError : Exception
{	/// Throws an exception with the current line number and an error message.
	this(uint lineNumber, char[] msg)
	{	super("(Line " ~ .toString(lineNumber) ~ ")" ~ msg);
	}
}

/**
 * XmlNode represents a single xml node and has methods for modifying
 * attributes and adding children.  All methods that make changes modify this
 * XmlNode rather than making a copy, unless otherwise noted.  Many methods
 * return a self reference to allow cascaded calls.
 * Example:
 * --------------------------------
 * // Create an XmlNode tree with attributes and cdata, and write it to a file.
 * node.addChild(new XmlNode("mynode").setAttribute("x", 50).
 *     addChild(new XmlNode("Waldo").addCdata("Hello!"))).write("myfile.xml");
 * --------------------------------*/
class XmlNode
{
    protected char[] _name;
    protected char[][char[]] _attributes;
    protected XmlNode[]      _children;
    protected static RegExp  _attribRe;
    protected static RegExp  _attribSplitRe;
    protected static RegExp trim_trailing_quote;

    /// A specialialized XmlNode for CData.
	class CData : XmlNode
	{
		private char[] _cdata;

		this(char[] cdata)
		{	_cdata = xmlDecode(cdata);
		}

		bool isCData()
		{	return true;
		}

		char[] getCData()
		{	return _cdata;
		}

		protected override char[] printCompact()
		{
			return xmlEncode(_cdata);
		}

	}

	static this()
	{	// disallowed attribute values are "<>%
		_attribRe = new RegExp("([a-z0-9]+)\\s*=\\s*\"([^\"^<^>^%]+)\"\\s*", "gim");
		_attribSplitRe = new RegExp("\\s*=\\s*\"", ""); // splits so an
		trim_trailing_quote = new RegExp("\"\\s*");
	}

	/// Construct an empty XmlNode.
	this()
	{}

	/// Construct and set the name of this XmlNode to name.
	this(char[] name)
	{	_name = name;
	}

	/// Get the name of this XmlNode.
	char[] getName()
	{	return _name;
	}

	/// Set the name of this XmlNode.
	void setName(char[] newName)
	{	_name = newName;
	}

	/// Does this XmlNode have an attribute with name?
	bool hasAttribute(char[] name)
	{	return (name in _attributes) !is null;
	}

	/// Get the attribute with name, or return null if no attribute has that name.
	char[] getAttribute(char[] name)
	{	if (name in _attributes)
			return _attributes[name];
		else
			return null;
	}

	/// Return an array of all attributes (by reference, no copy is made).
	char[][char[]] getAttributes()
	{	return _attributes;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	XmlNode setAttribute(char[] name, char[] value)
	{	_attributes[name] = value;
		return this;
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(char[] name, int value)
	{	return setAttribute(name, std.string.toString(value));
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(char[] name, float value)
	{	return setAttribute(name, std.string.toString(value));
	}

	/// Remove the attribute with name.
	XmlNode removeAttribute(char[] name)
	{	_attributes.remove(name);
		return this;
	}

	/// Add an XmlNode child.
	XmlNode addChild(XmlNode newNode)
	{	_children ~= newNode;
		return this;
	}

	/// Return an array of all child XmlNodes.
	XmlNode[] getChildren()
	{	return _children;
	}

	/// Add a child Node of cdata (text).
	XmlNode addCdata(char[] cdata)
	{	addChild(new CData(cdata));
		return this;
	}

	bool isCData()
	{	return false;
	}

	protected char[] asOpenTag()
	{
		if (_name.length == 0) {
			return "";
		}
		char[] s = "<" ~ _name;

		if (_attributes.length > 0)
		{	char[][] k = _attributes.keys;
			char[][] v = _attributes.values;
			for (int i = 0; i < _attributes.length; i++)
				s ~= " " ~ k[i] ~ "=\"" ~ v[i] ~ "\"";
		}

		if (_children.length == 0)
			s ~= " /"; // We want <blah /> if the node has no children.
		s ~= ">";

		return s;
	}

	protected char[] asCloseTag()
	{
		if (_name.length == 0) {
			return "";
		}
		if (_children.length != 0)
			return "</" ~ _name ~ ">";
		else
			return ""; // don't need it.  Leaves close themselves via the <blah /> syntax.
	}

	protected bool isLeaf()
	{	return _children.length == 0;
	}

	char[] printCompact()
	{
		char[]tmp = asOpenTag();

		if (_children.length)
		{
			for (int i = 0; i < _children.length; i++)
			{
				tmp ~= _children[i].printCompact(); 
			}
			tmp ~= asCloseTag();
		}
		return tmp;
	}

	void addChildren(char[]xsrc) {
		while (xsrc.length) {
			// there may be multiple tag trees or cdata elements
			parseNode(this,xsrc);
		}
	}

	// returns everything after the first node tree (a node can be text as well)
	private char[] parseNode(XmlNode parent,char[]xsrc) {
		char[] cdata = stripText(xsrc);
		if (cdata.length){
			parent.addCdata(cdata);
			return xsrc;
		}
		// look for a *REAL* cdata tag
		if (auto m = std.regexp.search(xsrc, "^<[CDATA[.*?]]>")) {
			parent.addCdata(m.match(0)[8..m.match(0).length-4]);
			return m.post;
		}
		// look for processing instructions
		if (auto m = std.regexp.search(xsrc, "^<\\?.*?\\?>")) {
			return m.post;
		}
		// look for comments or other xml instructions
		if (auto m = std.regexp.search(xsrc, "^<!.*?>")) {
			return m.post;
		}
		if (auto m = std.regexp.search(xsrc, "^<.*?>")) {
			char[]contents=m.match(0)[1..m.match(0).length-2];
			// check for self-closing tag
			bool selfclosing = false;
			if (contents[contents.length-1] == '/') {
				// strip off the trailing / and go about business as normal
				contents = contents[0..contents.length-2];
				selfclosing = true;
			}
			char[]name = getNextToken(contents);
			eatWhiteSpace(contents);
			XmlNode newnode = new XmlNode(name);
			// ats is a fun variable (attribute status) 0=nothing,1=attr,2=trans,3=value,4=quoting
			int ats = 0;
			char[]attr = "";
			char[]value = "";
			foreach (char x;contents) {
				// be warned, even though commented, this logic flow is ugly and probably needs to be redone
				if (isWhiteSpace(x) && ats != 4) {
					if (ats == 3) {
						// just finished a nonquoted attribute value
						newnode.setAttribute(attr,value);
						attr = "";
						value = "";
						ats = 0;
					} else if (ats != 0) {
						// we have a problem here....a space in the middle of our attribute
						// throw a malformed attribute exception
					}
					continue;
				}
				if (x == '"') {
					// jump onto a quoted value
					if (ats == 2) {
						ats = 4;
					} else if (ats == 4) {
						// we just finished a quoting section which means that we have a properly formed attribute
						newnode.setAttribute(attr,value);
						attr = "";
						value = "";
						// because of the way this is done, quoted attributes can be stacked with no whitespace
						// even though it may not be in the spec to allow that
						ats = 0;
						continue;
					} else {
						// we have a quote in the WRONG place
						// throw a malformed attribute exception
					}
				}
				// cover the transition from attribute name to value
				if (ats == 1 && x == '=') {
					ats = 2;
					continue;
				}
				// come off the transition onto the unquoted value
				if (ats == 2) {
					ats = 3;
					continue;
				}
				if (ats == 3 || ats == 4) {
					value ~= x;
					continue;
				}
				if (ats == 1) {
					attr ~= x;
					continue;
				}
			}
			char[]ret = "";
			if (!selfclosing) {
				// now that we've added all the attributes to the node, pass the m.post string and the current node to the next node
				// probably need to catch and rethrow exceptions here for a proper backtrace
				ret = parseNode(newnode,m.post);
				// since everything has returned successfully so far, try to parse out my closing tag
				// if we can find the closing tag, that means we can add our node to the parent and finish with this
				if (auto m = std.regexp.search(ret, "^</"~name~">")) {
					parent.addChild(newnode);
					return m.post;
				} else {
					// throw a missing closing tag exception
				}
			}
			return m.post;
		} else {
			// throw an exception cause we have a <, but no matching >
		}
	}

	char[]stripText(inout char[] xsrc) {
		char[]ret = "";
		if (xsrc[0] == '<') {
			return ret;
		}
		if (auto m = std.regexp.search(xsrc, "^.*?<")) {
			xsrc = m.post;
			return m.match(0);
		} else {
			ret = xsrc;
			xsrc.length = 0;
			return ret;
		}
	}

	char[]getNextToken(inout char[]input) {
		eatWhiteSpace(input);
		char[]ret = "";
		while (!isWhiteSpace(input[0])) {
			ret ~= input[0];
			input = input[1..input.length-1];
		}
		return ret;
	}

	void eatWhiteSpace(inout char[]input) {
		while (isWhiteSpace(input[0])) {
			input = input[1..input.length-1];
		}
	}

	int isWhiteSpace(char checkspace) {
		if (checkspace == '\u0020' || checkspace == '\u0009' || checkspace == '\u000A' || checkspace == '\u000D') {
			return 1;
		}
		return 0;
	}
}

/// Encode characters such as &, <, >, etc. as their xml/html equivalents
char[] xmlEncode(char[] src)
{   char[] tempStr;
        tempStr = replace(src    , "&", "&amp;");
        tempStr = replace(tempStr, "<", "&lt;");
        tempStr = replace(tempStr, ">", "&gt;");
        return tempStr;
}

/// Convert xml-encoded special characters such as &amp;amp; back to &amp;.
char[] xmlDecode(char[] src)
{       char[] tempStr;
        tempStr = replace(src    , "&amp;", "&");
        tempStr = replace(tempStr, "&lt;",  "<");
        tempStr = replace(tempStr, "&gt;",  ">");
        return tempStr;
}

