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

module xml;

import std.string;
import std.stdio;
import std.ctype:isspace;

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

	// Construct an empty XmlNode.
	this(){}

	// Construct and set the name of this XmlNode to name.
	this(char[] name) {
		_name = name;
	}

	// Get the name of this XmlNode.
	char[] getName() {
		return _name;
	}

	// Set the name of this XmlNode.
	void setName(char[] newName) {
		_name = newName;
	}

	// Does this XmlNode have an attribute with name?
	bool hasAttribute(char[] name) {
		return (name in _attributes) !is null;
	}

	// Get the attribute with name, or return null if no attribute has that name.
	char[] getAttribute(char[] name) {
		if (name in _attributes)
			return xmlDecode(_attributes[name]);
		else
			return null;
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	char[][char[]] getAttributes() {
		char[][char[]]tmp;
		// this is inefficient as it is run every time, but doesn't hurt parsing speed
		foreach(key;_attributes.keys) {
			tmp[key] = xmlDecode(_attributes[key]);
		}
		return tmp;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	XmlNode setAttribute(char[] name, char[] value) {
		_attributes[name] = xmlEncode(value);
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

	// Remove the attribute with name.
	XmlNode removeAttribute(char[] name) {
		_attributes.remove(name);
		return this;
	}

	// Add an XmlNode child.
	XmlNode addChild(XmlNode newNode) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length+1%10==0) {
			_children.length = _children.length + 10;
			_children.length = _children.length - 10;
		}
		_children.length = _children.length + 1;
		_children[$-1] = newNode;
		return this;
	}

	// Return an array of all child XmlNodes.
	XmlNode[] getChildren() {
		return _children;
	}

	// remove the child with the same reference as what was given, returns the number of children removed
	int removeChild(XmlNode remove) {
		int len = _children.length;
		for (int i = 0;i<_children.length;i++) if (_children[i] is remove) {
			// we matched it, so remove it
			// don't return true yet, since we're removing all references to it, not just the first one
			_children = _children[0..i]~_children[i+1..$];
		}
		return len - _children.length;
	}

	// Add a child Node of cdata (text).
	XmlNode addCdata(char[] cdata) {
		addChild(new CData(cdata));
		return this;
	}

	// make an alias so as not to break compatibility
	XmlNode addCData(char[] cdata) {
		return addCdata(cdata);
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

	// add array of nodes directly into the current node
	void addChildren(XmlNode[]newChildren) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length+newChildren.length%10 < newChildren.length) {
			_children.length = _children.length + 10;
			_children.length = _children.length - 10;
		}
		_children.length = _children.length + newChildren.length;
		_children[$-newChildren.length..$] = newChildren[0..$];
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
		// ignore comments
		} else if (toktype == comment) {
			// do nothing, will return with 0 at the bottom
		// take care of real cdata tags and plain text
		} else if (toktype == pcdata || toktype == ucdata) {
			if (toktype == ucdata) {
				token = token[9..$-3];
			}
			debug(xml)writefln("I found cdata text: %s",token);
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
			debug(xml)writefln("Got a %s XML processing instruction",name);
			XmlPI newnode = new XmlPI(name);
			token = stripl(token);
			debug(xml)writefln("Attributes: %s",token);
			parseAttributes(newnode,token);
			parent.addChild(newnode);
		// look for comments or other xml instructions
		} else if (toktype == xmlinst) {
			// we don't do anything with xml instructions at the moment, so they're treated as comments
			debug(xml)writefln("I found a XML instruction!");
		// opening tags are caught here
		} else if (toktype == otag) {
			debug(xml)writefln("I found a XML tag: %s",token);
			token = token[1..$-1];
			debug(xml)writefln("Tag Contents: %s",token);
			// check for self-closing tag
			bool selfclosing = false;
			if (token[$-1] == '/') {
				// strip off the trailing / and go about business as normal
				token = token[0..$-1];
				selfclosing = true;
				debug(xml)writefln("self-closing tag!");
			}
			char[]name = getWSToken(token);
			debug(xml)writefln("It was a %s tag!",name);
			token = stripl(token);
			debug(xml)writefln("Attributes: %s",token);
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
				// this is where we can get sloppy for stream parsing
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
		ctag,
		comment
	};
	// this grabs the next token, being either unparsed cdata, parsed cdata, an xml or processing instruction, or a normal tag
	// for performance reasons, this should spit out a fully formed xml node, should get a 1.5x speed increase
	// XXX this function needs rework to be more efficient
	private int getXmlToken(inout char[] xsrc, inout char[] token) {
		int slice;
		xsrc = stripl(xsrc);
		if (!xsrc.length) {
			return notoken;
		}
		if (xsrc[0] != '<') {
			slice = readUntil(xsrc,"<");
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return pcdata;
		// types of tags, gotta make sure we find the closing > (or ]]> in the case of ucdata)
		// check for the opening tag first, because it's most likely
		} else if (xsrc[1] != '!' && xsrc[1] != '?' && xsrc[1] != '/') {
			// just a regular old tag
			slice = readUntil(xsrc,">");
			slice += ">".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return otag;
		} else if (xsrc[1] == '/') {
			// closing tag!
			slice = readUntil(xsrc,">");
			slice += ">".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return ctag;
		} else if (xsrc[1] == '?') {
			// processing instruction!
			slice = readUntil(xsrc,"?>");
			slice += "?>".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return procinst;
		// 12 is the magic number that allows for the empty cdata string ![CDATA[]]>
		} else if (xsrc.length >= 12 && xsrc[1..9].cmp("![CDATA[") == 0) {
			// unparsed cdata!
			slice = readUntil(xsrc,"]]>");
			slice += "]]>".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return ucdata;
		// make sure we parse out comments, minimum length for this is 7 (<!---->)
		} else if (xsrc.length >= 7 && xsrc[1..4].cmp("!--") == 0) {
			// a comment...which will just get ignored later
			slice = readUntil(xsrc,"-->");
			slice += "-->".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return comment;
		} else if (xsrc[1] == '!') {
			// xml instruction!
			slice = readUntil(xsrc,">");
			slice += ">".length;
			if (slice>xsrc.length) slice = xsrc.length;
			token = xsrc[0..slice];
			xsrc = xsrc[slice..$];
			return xmlinst;
		}
	}

	// read data until the delimiter is found, return the index where the delimiter starts
	private int readUntil(char[]xsrc, char[]delim) {
		// the -delim.length is partially optimization and partially avoiding jumping the array bounds
		int i = xsrc.find(delim);
		// yeah...if we didn't find it, then the whole string is the token :D
		if (i == -1) {
			return xsrc.length;
		}
		return i;
	}

	// basically to get the name off of open tags
	private char[]getWSToken(inout char[]input) {
		input = stripl(input);
		int i;
		for(i=0;input.length > i && !isspace(input[i]);i++){}
		auto ret = input[0..i];
		input = input[i..$];
		return ret;
	}

	// this code is now officially prettified
	private void parseAttributes (XmlNode xml,char[]attrstr) {
		char[]ripName(inout char[]input) {
			int i;
			for(i=0;i < input.length && !isspace(input[i]) && input[i] != '=';i++){}
			auto ret = input[0..i];
			input = input[i..$];
			return ret;
		}
		char[]ripValue(inout char[]input) {
		        int x;
			char quot = input[0];
			// rip off the starting quote
		        input = input[1..$];
			// find the end of the string we want
		        for(x = 0;(input[x] != quot || (input[x] == quot && x && input[x-1] == '\\')) && x < input.length;x++) {
		        }
		        char[]tmp = input[0..x];
			// add one to leave off the quote
		        input = input[x+1..$];
		        return tmp;
		}

		attrstr = stripl(attrstr);
		while(attrstr.length) {
			// snag the name from the attribute string
			char[]value,name = ripName(attrstr);
			attrstr = stripl(attrstr);
			// check for = to make sure the attribute string is kosher
			if (!attrstr.length) throw new XmlError("Unexpected end of attribute string near "~name);
			if (attrstr[0] != '=') throw new XmlError("Missing = in attribute string with name "~name);
			// rip off =
			attrstr = attrstr[1..$];
			attrstr = stripl(attrstr);
			if (attrstr.length && (attrstr[0] == '"' || attrstr[0] == '\'')) {
				value = ripValue(attrstr);
			} else {
				value = getWSToken(attrstr);
			}
			xml.setAttribute(name,value);
			attrstr = stripl(attrstr);
		}
	}

	XmlNode[]parseXPath(char[]xpath,bool caseSensitive = false) {
		// rip off the leading / if it's there and we're not looking for a deep path
		if (!isDeepPath(xpath) && xpath.length && xpath[0] == '/') xpath = xpath[1..$];
		debug(xpath) writefln("Got xpath %s in node %s",xpath,getName);
		char[]truncxpath;
		char[]nextnode = getNextNode(xpath,truncxpath);
		char[]attrmatch = "";
		// need to be able to split the attribute match off even when it doesn't have [] around it
		int offset = nextnode.find('[');
		if (offset != -1) {
			// rip out attribute string
			attrmatch = nextnode[offset..$];
			nextnode = nextnode[0..offset];
			debug(xpath) writefln("Found attribute chunk: %s\n",attrmatch);
		}
		debug(xpath) writefln("Looking for %s",nextnode);
		XmlNode[]retarr;
		// search through the children to see if we have a direct match on the next node
		if (!nextnode.length) {
			// we were searching for nodes, and this is one
			debug(xpath) writefln("Found a node we want! name is: %s",getName);
			retarr ~= this;
		} else foreach(child;getChildren) if (!child.isCData && child.matchXPathAttr(attrmatch,caseSensitive)) {
			if (!nextnode.length || (caseSensitive && child.getName == nextnode) || (!caseSensitive && !child.getName().icmp(nextnode))) {
				// child that matches the search string, pass on the truncated string
				debug(xpath) writefln("Sending %s to %s",truncxpath,child.getName);
				retarr ~= child.parseXPath(truncxpath,caseSensitive);
			}
		}
		// we aren't on us, but check to see if we're looking for a deep path, and delve in accordingly
		// currently this means, the entire tree could be traversed multiple times for a single query...eww
		// and the query // should generate a list of the entire tree, in the order the elements specifically appear
		if (isDeepPath(xpath)) foreach(child;getChildren) if (!child.isCData) {
			// throw the exact same xpath at each child
			retarr ~= child.parseXPath(xpath,caseSensitive);
		}
		return retarr;
	}

	private bool matchXPathAttr(char[]attrstr,bool caseSen) {
		debug(xpath)writefln("matching attribute string %s",attrstr);
		if (attrstr.length < 2) {
			// if there's no attribute list to check, then it matches
			return true;
		}
		// right now, this can only handle simple attribute matching
		// i.e. no subnode matches, otherwise, the / in the subnode match will make things explode...badly
		// strip off the encasing [] if it exists
		if (attrstr[0] == '[' && attrstr[$-1] == ']') {
			attrstr = attrstr[1..$-1];
		} else if (attrstr[0] == '[' || attrstr[$-1] == ']') {
			// this seems to be malformed
			debug(xpath)writefln("got malformed attribute match %s",attrstr);
			return false;
		}
		if (attrstr.length < 2) {
			// if there's no attribute list to check, then it matches
			return true;
		}
		char[][]attrlist = attrstr.split(" and ");
		foreach(attr;attrlist) {
			debug(xpath)writefln("matching on %s",attr);
			char[]datamatch = "";
			int sep = attr.find('=');
			// strip off the @ and separate the attribute and value if it exists
			if (sep != -1) {
				datamatch = attr[sep+1..$];
				if (datamatch.length && datamatch[0] == '"' && datamatch[$-1] == '"') {
					datamatch = datamatch[1..$-1];
				}
				attr = attr[1..sep];
			} else {
				attr = attr[1..$];
			}
			// the !attr.length is just a precaution for the idiots that would do it
			if (!attr.length || !hasAttribute(attr)) {
				debug(xpath)writefln("could not find %s",attr);
				return false;
			}
			if (datamatch.length) {
				if ((getAttribute(attr) != datamatch && caseSen) || (getAttribute(attr).icmp(datamatch) != 0 && !caseSen)) {
					debug(xpath)writefln("search value %s did not match attribute value %s",datamatch,getAttribute(attr));
					return false;
				}
			}
		}
		return true;
	}
	
	private bool isDeepPath(char[]xpath) {
		// check to see if we're currently searching a deep path
		if (xpath.length > 1 && xpath[0] == '/' && xpath[1] == '/') {
			return true;
		}
		return false;
	}

	// this does not modify the incoming string, only pulls a slice out of it
	private char[]getNextNode(char[]xpath,out char[]truncxpath) {
		if (isDeepPath(xpath)) xpath = xpath[2..$];
		char[][]nodes = std.string.split(xpath,"/");
		if (nodes.length) {
			// leading slashes will be removed in recursive calls 
			if (nodes.length > 1) truncxpath = xpath[nodes[0].length..$];
			return nodes[0];
		}
		// i'm not sure this can occur unless the string was blank to begin with...
		truncxpath = "";
		return "";
	}
}

// class specializations for different types of nodes, such as cdata and instructions
// A node type for CData.
class CData : XmlNode
{
	private char[] _cdata;

	this(char[] cdata) {
		_cdata = cdata;
	}

	override bool isCData() {
		return true;
	}

	override char[] getCData() {
		return xmlDecode(_cdata);
	}

	CData setCData(char[]cdata) {
		_cdata = xmlEncode(cdata);
		return this;
	}

	protected override char[] toString() {
		return _cdata;
	}

	protected override char[] write(char[]indent) {
		return indent~toString()~"\n";
	}

	protected char[] asCloseTag() { return ""; }

	protected bool isLeaf() {
		return true;
	}

	override char[] getName() {
		throw new XmlError("CData nodes do not have names to get.");
		return "";
	}

	// Set the name of this XmlNode.
	override void setName(char[] newName) {
		throw new XmlError("CData nodes do not have names to set.");
	}

	// Does this XmlNode have an attribute with name?
	override bool hasAttribute(char[] name) {
		throw new XmlError("CData nodes do not have attributes.");
		return false;
	}

	// Get the attribute with name, or return null if no attribute has that name.
	override char[] getAttribute(char[] name) {
		throw new XmlError("CData nodes do not have attributes to get.");
		return null;
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	override char[][char[]] getAttributes() {
		throw new XmlError("CData nodes do not have attributes to get.");
		return null;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	override XmlNode setAttribute(char[] name, char[] value) {
		throw new XmlError("CData nodes do not have attributes to set.");
		return null;
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(char[] name, int value) {
		throw new XmlError("CData nodes do not have attributes to set.");
		return null;
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(char[] name, float value) {
		throw new XmlError("CData nodes do not have attributes to set.");
		return null;
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to CData.");
		return null;
	}

	// Add a child Node of cdata (text).
	override XmlNode addCdata(char[] cdata) {
		throw new XmlError("Cannot add a child node to CData.");
		return null;
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(char[] cdata) {
		throw new XmlError("Cannot add a child node to CData.");
		return null;
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

	protected char[] asCloseTag() { return ""; }

	protected bool isLeaf() {
		return true;
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to XmlPI.");
		return null;
	}

	// Add a child Node of cdata (text).
	override XmlNode addCdata(char[] cdata) {
		throw new XmlError("Cannot add a child node to XmlPI.");
		return null;
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(char[] cdata) {
		throw new XmlError("Cannot add a child node to XmlPI.");
		return null;
	}
}

// A node type for xml instructions.
class XmlComment : XmlNode {
	char[]comment;
	this(char[]incomment) {
		comment = incomment;
		super("");
	}

	override bool isXmlPI() {
		return false;
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
		char[] s = "<!--" ~ comment  ~ "-->";
		return s;
	}

	protected char[] asCloseTag() { return ""; }

	protected bool isLeaf() {
		return true;
	}

	override char[] getName() {
		throw new XmlError("Comment nodes do not have names to get.");
		return "";
	}

	// Set the name of this XmlNode.
	override void setName(char[] newName) {
		throw new XmlError("Comment nodes do not have names to set.");
	}

	// Does this XmlNode have an attribute with name?
	override bool hasAttribute(char[] name) {
		throw new XmlError("Comment nodes do not have attributes.");
		return false;
	}

	// Get the attribute with name, or return null if no attribute has that name.
	override char[] getAttribute(char[] name) {
		throw new XmlError("Comment nodes do not have attributes to get.");
		return null;
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	override char[][char[]] getAttributes() {
		throw new XmlError("Comment nodes do not have attributes to get.");
		return null;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	override XmlNode setAttribute(char[] name, char[] value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
		return null;
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(char[] name, int value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
		return null;
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(char[] name, float value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
		return null;
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to comment.");
		return null;
	}

	// Add a child Node of cdata (text).
	override XmlNode addCdata(char[] cdata) {
		throw new XmlError("Cannot add a child node to comment.");
		return null;
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(char[] cdata) {
		throw new XmlError("Cannot add a child node to comment.");
		return null;
	}
}


/// Encode characters such as &, <, >, etc. as their xml/html equivalents
char[] xmlEncode(char[] src) {
	char[] tempStr;
        tempStr = replace(src    , "&", "&amp;");
        tempStr = replace(tempStr, "<", "&lt;");
        tempStr = replace(tempStr, ">", "&gt;");
        tempStr = replace(tempStr, "\"", "&quot;");
        return tempStr;
}

/// Convert xml-encoded special characters such as &amp;amp; back to &amp;.
char[] xmlDecode(char[] src) {
	char[] tempStr;
        tempStr = replace(src    , "&lt;",  "<");
        tempStr = replace(tempStr, "&gt;",  ">");
        tempStr = replace(tempStr, "&quot;",  "\"");
        tempStr = replace(tempStr, "&amp;", "&");
        return tempStr;
}

unittest {
	char[]xmlstring = "<message responseID=\"1234abcd\" text=\"weather 12345\" type=\"message\"><flags>triggered</flags><flags>targeted</flags></message>";
	XmlNode xml = xmlstring.readDocument();
	xmlstring = xml.toString;
	// ensure that the string doesn't mutate after a second reading, it shouldn't
	debug(xml)writefln("kxml.xml unit test");
	assert(xmlstring.readDocument().toString == xmlstring);
	debug(xpath)writefln("kxml.xml XPath unit test");
	XmlNode[]searchlist = xml.parseXPath("message/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	debug(xpath)writefln("kxml.xml deep XPath unit test");
	searchlist = xml.parseXPath("//message//flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	debug(xpath)writefln("kxml.xml attribute match XPath unit test");
	searchlist = xml.parseXPath("/message[@type=\"message\" and @responseID=\"1234abcd\"]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("message[@type=\"toaster\"]/flags");
	assert(searchlist.length == 0);
}

