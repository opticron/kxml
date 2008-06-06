/**
 * Copyright:  (c) 2008 William K. Moore, III (opticron@the.narro.ws, I-MOD on IRC)
 * Authors:    Andy Friesen, William K. Moore, III
 * License:    <a href="lgpl.txt">LGPL</a>
 *
 * Xml contains functions and classes for reading, parsing, and writing xml
 * documents.
 *
 * History:
 * Most of the code in this module originally came from Andy Friesen's Xmld.
 * Xmld was unmaintained, but Andy had placed it in the public domain.  This 
 * code builds off the Yage work to remain mostly API compatible, but the
 * internal parser has been completely rewritten.
 */

module KXML.xml;

import std.string;
import std.stdio;

/**
 * Read an entire string into a tree of XmlNodes.
 * Example:
 * --------------------------------
 * XmlNode xml;
 * char[]xmlstring = "<node attr="self closing"/>";
 * xml = readDocument(xmlstring);
 * --------------------------------*/
XmlNode readDocument(char[]src)
{
	XmlNode root = new XmlNode("");
	root.addChildren(src);
	return root;
}

// An exception thrown on an xml parsing error.
class XmlError : Exception {
	// Throws an exception with the current line number and an error message.
	this(char[] msg) {
		super(msg);
	}
}

// An exception thrown on an xml parsing error.
class XmlMalformedAttribute : XmlError {
	/// Throws an exception with the current line number and an error message.
	this(char[]part,char[] msg) {
		super("Malformed Attribute " ~ part ~ ": " ~ msg ~ "\n");
	}
}
/// An exception thrown on an xml parsing error.
class XmlMalformedSubnode : XmlError {
	// Throws an exception with the current line number and an error message.
	this(char[] name) {
		super("Malformed Subnode of " ~ name);
	}
}
/// An exception thrown on an xml parsing error.
class XmlMissingEndTag : XmlError {
	// Throws an exception with the current line number and an error message.
	this(char[] name) {
		super("Missing End Tag " ~ name ~ "\n");
	}
}
/// An exception thrown on an xml parsing error.
class XmlCloseTag : XmlError {
	// Throws an exception with the current line number and an error message.
	this() {
		super("");
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


	protected char[] genAttrString() {
		char[]ret;
		foreach (keys,values;_attributes) {
				ret ~= " " ~ keys ~ "=\"" ~ values ~ "\"";
		}
		return ret;
	}

	static this(){}

	/// Construct an empty XmlNode.
	this(){}

	/// Construct and set the name of this XmlNode to name.
	this(char[] name) {
		_name = name;
	}

	/// Get the name of this XmlNode.
	char[] getName() {
		return _name;
	}

	/// Set the name of this XmlNode.
	void setName(char[] newName) {
		_name = newName;
	}

	/// Does this XmlNode have an attribute with name?
	bool hasAttribute(char[] name) {
		return (name in _attributes) !is null;
	}

	/// Get the attribute with name, or return null if no attribute has that name.
	char[] getAttribute(char[] name) {
		if (name in _attributes)
			return _attributes[name];
		else
			return null;
	}

	/// Return an array of all attributes (by reference, no copy is made).
	char[][char[]] getAttributes() {
		return _attributes;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	XmlNode setAttribute(char[] name, char[] value) {
		_attributes[name] = value;
		return this;
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(char[] name, int value) {
		return setAttribute(name, std.string.toString(value));
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(char[] name, float value) {
		return setAttribute(name, std.string.toString(value));
	}

	/// Remove the attribute with name.
	XmlNode removeAttribute(char[] name) {
		_attributes.remove(name);
		return this;
	}

	/// Add an XmlNode child.
	XmlNode addChild(XmlNode newNode) {
		_children ~= newNode;
		return this;
	}

	/// Return an array of all child XmlNodes.
	XmlNode[] getChildren() {
		return _children;
	}

	/// Add a child Node of cdata (text).
	XmlNode addCdata(char[] cdata) {
		addChild(new CData(cdata));
		return this;
	}

	// this should be done with casting tests
	bool isCData() {
		return false;
	}

	// this should be done with casting tests
	bool isXmlPI() {
		return false;
	}

	// this makes life easier for those looking to pull cdata from tags that only have that as the single subnode
	char[]getCData() {
		if (_children.length && _children[0].isCData) {
			return _children[0].getCData;
		} else {
			return "";
		}
	}

	protected char[] asOpenTag() {
		if (_name.length == 0) {
			return "";
		}
		char[] s = "<" ~ _name ~ genAttrString();

		if (_children.length == 0)
			s ~= " /"; // We want <blah /> if the node has no children.
		s ~= ">";

		return s;
	}

	protected char[] asCloseTag() {
		if (_name.length == 0) {
			return "";
		}
		if (_children.length != 0)
			return "</" ~ _name ~ ">";
		else
			return ""; // don't need it.  Leaves close themselves via the <blah /> syntax.
	}

	protected bool isLeaf() {
		return _children.length == 0;
	}

	// this is a dump of the xml structure to a string with no newlines and no linefeeds
	char[] toString() {
		char[]tmp = asOpenTag();

		if (_children.length)
		{
			for (int i = 0; i < _children.length; i++)
			{
				tmp ~= _children[i].toString(); 
			}
			tmp ~= asCloseTag();
		}
		return tmp;
	}

	// this is a dump of the xml structure in to pretty, tabbed format
	char[] write(char[]indent="") {
		char[]tmp = indent~asOpenTag()~"\n";

		if (_children.length)
		{
			for (int i = 0; i < _children.length; i++)
			{
				// these guys are supposed to do their own indentation
				tmp ~= _children[i].write(indent~"	"); 
			}
			tmp ~= indent~asCloseTag()~"\n";
		}
		return tmp;
	
	}

	// add children from a character array containing xml
	void addChildren(char[]xsrc) {
		while (xsrc.length) {
			// there may be multiple tag trees or cdata elements
			parseNode(this,xsrc);
		}
	}

	// returns everything after the first node TREE (a node can be text as well)
	private int parseNode(XmlNode parent,inout char[]xsrc) {
		// if it was just whitespace and no more text or tags, make sure that's covered
		if (!xsrc.length) {
			return 0;
		}
		char[] token;
		int toktype = getXmlToken(xsrc,token);
		if (toktype == notoken) {
			xsrc = "";
		// take care of real cdata tags and plain text
		} else if (toktype == pcdata || toktype == ucdata) {
			if (toktype == ucdata) {
				token = token[9..$-3];
			}
			debug(xml)writefln("I found cdata text: "~token);
			parent.addCdata(token);
		// look for a closing tag to see if we're done
		} else if (toktype == ctag) {
			debug(xml)writefln("I found a closing tag (yikes):%s!",token);
			if (token[2..$-1].icmp(parent.getName()) == 0) {
				return 1;
			} else {
				throw new XmlError("Wrong close tag?");
			}
		// look for processing instructions
		} else if (toktype == procinst) {
			// all processing instructions are leaf nodes, which makes things a bit more simple than regular nodes
			// strip off the tokens that identify a xml PI node
			token = token[2..$-2];
			char[]name = getWSToken(token);
			debug(xml)writefln("Got a "~name~" XML processing instruction");
			XmlPI newnode = new XmlPI(name);
			eatWhiteSpace(token);
			debug(xml)writefln("Attributes: "~token);
			parseAttributes(newnode,token);
			parent.addChild(newnode);
		// look for comments or other xml instructions
		} else if (toktype == xmlinst) {
			// we don't do anything with xml instructions at the moment, so they're treated as comments
			debug(xml)writefln("I found a XML instruction!");
		// opening tags are caught here
		} else if (toktype == otag) {
			debug(xml)writefln("I found a XML tag: "~token);
			token = token[1..$-1];
			debug(xml)writefln("Tag Contents: "~token);
			// check for self-closing tag
			bool selfclosing = false;
			if (token[$-1] == '/') {
				// strip off the trailing / and go about business as normal
				token = token[0..$-1];
				selfclosing = true;
				debug(xml)writefln("self-closing tag!");
			}
			char[]name = getWSToken(token);
			debug(xml)writefln("It was a "~name~" tag!");
			eatWhiteSpace(token);
			debug(xml)writefln("Attributes: "~token);
			XmlNode newnode = new XmlNode(name);
			parseAttributes(newnode,token);
			if (!selfclosing) {
				// now that we've added all the attributes to the node, pass the rest of the string and the current node to the next node
				int ret;
				try {
					while (xsrc.length) {
						if ((ret = parseNode(newnode,xsrc)) == 1) {
							break;
						}
					}
				} catch (Exception e) {
					throw new XmlMalformedSubnode(name~"\n"~e.toString());
				}
				// make sure we found our closing tag
				if (!ret) {
					// throw a missing closing tag exception
					throw new XmlMissingEndTag(name);
				}
			}
			parent.addChild(newnode);
		} else {
			// throw an exception cause we have a <, but no matching >
			throw new XmlError("Unable to pull a token, missing >");
		}
		return 0;
	}

	private enum {
		notoken=0,
		pcdata,
		ucdata,
		xmlinst,
		procinst,
		otag,
		ctag
	};
	// this grabs the next token, being either unparsed cdata, parsed cdata, an xml or processing instruction, or a normal tag
	// for performance reasons, this should spit out a fully formed xml node, should get a 1.5x speed increase
	private int getXmlToken(inout char[] xsrc, inout char[] token) {
		eatWhiteSpace(xsrc);
		if (!xsrc.length) {
			return notoken;
		}
		if (xsrc[0] != '<') {
			token = readUntil(xsrc,"<");
			return pcdata;
		// types of tags, gotta make sure we find the closing > (or ]]> in the case of ucdata)
		} else if (xsrc[1] == '/') {
			// closing tag!
			token = readUntil(xsrc,">");
			if (!xsrc.length || xsrc[0] != '>') {
				return notoken;
			}
			xsrc = xsrc[1..$];
			token ~= ">";
			return ctag;
		} else if (xsrc[1] == '?') {
			// processing instruction!
			token = readUntil(xsrc,"?>");
			if (!xsrc.length || xsrc[0..2].cmp("?>") != 0) {
				return notoken;
			}
			xsrc = xsrc[2..$];
			token ~= "?>";
			return procinst;
		// 12 is the magic number that allows for the empty cdata string ![CDATA[]]>
		} else if (xsrc.length >= 12 && xsrc[1..9].cmp("![CDATA[") == 0) {
			// unparsed cdata!
			token = readUntil(xsrc,"]]>");
			if (!xsrc.length || xsrc[0..3].cmp("]]>") != 0) {
				return notoken;
			}
			xsrc = xsrc[3..$];
			token ~= "]]>";
			return ucdata;
		} else if (xsrc[1] == '!') {
			// xml instruction!
			token = readUntil(xsrc,">");
			if (!xsrc.length || xsrc[0] != '>') {
				return notoken;
			}
			xsrc = xsrc[1..$];
			token ~= ">";
			return xmlinst;
		} else {
			// just a regular old tag
			token = readUntil(xsrc,">");
			if (!xsrc.length || xsrc[0] != '>') {
				return notoken;
			}
			xsrc = xsrc[1..$];
			token ~= ">";
			return otag;
		}
	}

	// read data until the delimiter is found, if found the delimiter is left on the first parameter
	private char[]readUntil(inout char[]xsrc, char[]delim) {
		// the -delim.length is partially optimization and partially avoiding jumping the array bounds
		int i;
		for (i = 0;i<xsrc.length-delim.length;i++) {
			if (xsrc[i..i+delim.length].cmp(delim) == 0) {
				break;
			}
		}
		// i could put this inside the loop, but it probably runs faster with it outside
		if (i == 0) {
			return "";
		}
		// and now to split up the string
		// latter part of the string gets the delimiter
		char[]token;
		token = xsrc[0..i];
		xsrc = xsrc[i..$];
		return token;
	}

	// basically to get the name off of open tags
	private char[]getWSToken(inout char[]input) {
		eatWhiteSpace(input);
		char[]ret = "";
		while (input.length > 0 && !isWhiteSpace(input[0])) {
			ret ~= input[0];
			input = input[1..input.length];
		}
		return ret;
	}

	// eats tabs, newlines, and spaces until the next normal character
	private void eatWhiteSpace(inout char[]input) {
		while (input.length > 0 && isWhiteSpace(input[0])) {
			input = input[1..input.length];
		}
	}

	// lets you know if the character is a whitespace character
	private int isWhiteSpace(char checkspace) {
		if (checkspace == '\u0020' || checkspace == '\u0009' || checkspace == '\u000A' || checkspace == '\u000D') {
			return 1;
		}
		return 0;
	}

	// dont look at this code, it WILL hurt (i need to use an enum to make things prettier)
	// this needs to be redone as I believe it is a significant part of what is causing the poor performance
	private void parseAttributes (XmlNode xml,char[]contents) {
		enum {
			whitespace=0,
			name=1,
			// name/value transition (=)
			nvtrans=2,
			// unquoted value
			value=3,
			// double quoted value
			dqval=4,
			// single quoted value
			sqval=5
		};
		// ats is a fun variable (attribute status) 0=nothing,1=attr,2=trans,3=value,4=double quoting,5=single quoting
		int ats = whitespace;
		char[]attr = "";
		char[]attrval = "";
		foreach (char x;contents) {
			// be warned, even though commented, this logic flow is ugly and probably needs to be redone
			// it probably doesn't handle escape codes properly either....
			// check for the quote escape
			if (x == '\\' && ats != dqval && ats != sqval) {
				// why is there a backslash here?
				if (ats == value) {
					throw new XmlMalformedAttribute("Value",attrval~x);
				} else {
					throw new XmlMalformedAttribute("Name",attr~x);
				}
			}
			if (isWhiteSpace(x) && ats != dqval) {
				if (ats == value) {
					// just finished a nonquoted attribute value
					xml.setAttribute(attr,attrval);
					debug(xml)writefln("Got attribute %s with value %s",attr,attrval);
					attr = "";
					attrval = "";
					ats = whitespace;
				} else if (ats != whitespace) {
					// we have a problem here....a space in the middle of our attribute
					// throw a malformed attribute exception
					throw new XmlMalformedAttribute("Name",attr);
				}
				continue;
			}
			if (x == '"' || x == '\'') {
				int tmp = (x=='"'?dqval:sqval);
				// jump onto a quoted value
				if (ats == nvtrans) {
					debug(xml)writefln("began a quoted value!");
					ats = tmp;
					continue;
				} else if (ats == tmp) {
					// we just finished a quoting section which means that we have a properly formed attribute
					xml.setAttribute(attr,attrval);
					debug(xml)writefln("Got attribute %s with value %s",attr,attrval);
					attr = "";
					attrval = "";
					// because of the way this is done, quoted attributes can be stacked with no whitespace
					// even though it may not be in the spec to allow that
					ats = whitespace;
					continue;
				// we have a quote in the WRONG place
				} else if (ats == name) {
					// throw a malformed attribute exception
					throw new XmlMalformedAttribute("Name",attr~x);
				// we have a quote in the WRONG place
				} else if (ats == value) {
					throw new XmlMalformedAttribute("Value",attrval~x);
				} else if (ats == whitespace) {
					throw new XmlMalformedAttribute("Don't quote attribute names...","");
				// 
				} else {
					attrval ~= x;
					continue;
				}
			}
			// cover the transition from attribute name to value
			if (ats == name && x == '=') {
				//writefln("found end of attribute name!");
				ats = nvtrans;
				continue;
			}
			// come off the transition onto the unquoted value
			if (ats == nvtrans) {
				//writefln("found beginning of unquoted attribute value!");
				attrval ~= x;
				ats = value;
				continue;
			}
			if (ats == value || ats == dqval || ats == sqval) {
				attrval ~= x;
				continue;
			}
			if (ats == name || (!isWhiteSpace(x) && ats == whitespace)) {
				ats = name;
				attr ~= x;
				continue;
			}
		}
		if (ats == value) {
			// we have an unquoted value that happened to be the last attribute, so add it
			xml.setAttribute(attr,attrval);
			debug(xml)writefln("Got attribute %s with value %s",attr,attrval);
		}
		if (ats == dqval || ats == sqval) {
			// great...an unterminated quote
			throw new XmlMalformedAttribute("Value",attrval);
		}
		if (ats == nvtrans || ats == name) {
			// a name with no value...seriously, who does that?
			throw new XmlMalformedAttribute("Name with no value","");
		}
	}
}

// class specializations for different types of nodes, such as cdata and instructions
// A node type for CData.
class CData : XmlNode
{
	private char[] _cdata;

	this(char[] cdata) {
		_cdata = xmlDecode(cdata);
	}

	override bool isCData() {
		return true;
	}

	override char[] getCData() {
		return _cdata;
	}

	protected override char[] toString() {
		return xmlEncode(_cdata);
	}

	protected override char[] write(char[]indent) {
		return indent~toString()~"\n";
	}
}

// A node type for xml instructions.
class XmlPI : XmlNode {
	this(char[]name) {
		super(name);
	}

	override bool isXmlPI() {
		return true;
	}

	override char[] getCData() {
		return "";
	}
	override char[] toString() {
		return asOpenTag();
	}

	protected override char[] write(char[]indent="") {
		return indent~asOpenTag()~"\n";
	}
	protected char[] asOpenTag() {
		if (_name.length == 0) {
			return "";
		}
		char[] s = "<?" ~ _name ~ genAttrString() ~ "?>";
		return s;
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

