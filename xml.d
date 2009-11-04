/**
 * Copyright:  (c) 2009 William K. Moore, III (nyphbl8d (at) gmail (dot) com, opticron on freenode)
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

module kxml.xml;
version(Tango) {
	import tango.text.Util:isspace=isSpace,stripl=triml,strip=trim,stripr=trimr,find=locatePattern,split,replace=substitute;
	import tango.text.convert.Integer:tostring=toString;
	import tango.text.convert.Float:tostring=toString;
	import tango.text.Ascii:icmp=icompare,cmp=compare;
} else {
	version(D_Version2) {
		import std.conv:to;
		import std.string:strip,stripr,stripl,split,replace,find=indexOf,cmp,icmp,atoi;
	} else {
		import std.string:tostring=toString,strip,stripr,stripl,split,replace,find,cmp,icmp,atoi;
	}
	import std.stdio;
	import std.ctype:isspace;
	import std.regexp:sub,RegExp;
	import std.utf:toUTF8;
}

/**
 * Read an entire string into a tree of XmlNodes.
 * Example:
 * --------------------------------
 * XmlNode xml;
 * string xmlstring = "<node attr="self closing"/>";
 * xml = readDocument(xmlstring);
 * --------------------------------*/
XmlNode readDocument(string src)
{
	XmlNode root = new XmlNode(null);
	root.addChildren(src);
	return root;
}

// An exception thrown on an xml parsing error.
class XmlError : Exception {
	// Throws an exception with the current line number and an error message.
	this(string msg) {
		super(msg);
	}
}

// An exception thrown on an xml parsing error.
class XmlMalformedAttribute : XmlError {
	/// Throws an exception with the current line number and an error message.
	this(string part,string msg) {
		super("Malformed Attribute " ~ part ~ ": " ~ msg ~ "\n");
	}
}
/// An exception thrown on an xml parsing error.
class XmlMalformedSubnode : XmlError {
	// Throws an exception with the current line number and an error message.
	this(string name) {
		super("Malformed Subnode of " ~ name);
	}
}
/// An exception thrown on an xml parsing error.
class XmlMissingEndTag : XmlError {
	// Throws an exception with the current line number and an error message.
	this(string name) {
		super("Missing End Tag " ~ name ~ "\n");
	}
}
/// An exception thrown on an xml parsing error.
class XmlCloseTag : XmlError {
	// Throws an exception with the current line number and an error message.
	this() {
		super(null);
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
 *     addChild(new XmlNode("Waldo").addCData("Hello!"))).write("myfile.xml");
 * --------------------------------*/
class XmlNode
{
	protected string _name;
	protected string[string] _attributes;
	protected XmlNode[]      _children;


	protected string genAttrString() {
		string ret;
		foreach (keys,values;_attributes) {
				ret ~= " " ~ keys ~ "=\"" ~ values ~ "\"";
		}
		return ret;
	}

	static this(){}

	// Construct an empty XmlNode.
	this(){}

	// Construct and set the name of this XmlNode to name.
	this(string name) {
		_name = name;
	}

	// Get the name of this XmlNode.
	string getName() {
		return _name;
	}

	// Set the name of this XmlNode.
	void setName(string newName) {
		_name = newName;
	}

	// Does this XmlNode have an attribute with name?
	bool hasAttribute(string name) {
		return (name in _attributes) !is null;
	}

	// Get the attribute with name, or return null if no attribute has that name.
	string getAttribute(string name) {
		if (name in _attributes)
			return xmlDecode(_attributes[name]);
		else
			return null;
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	string[string] getAttributes() {
		string[string]tmp;
		// this is inefficient as it is run every time, but doesn't hurt parsing speed
		foreach(key;_attributes.keys) {
			tmp[key] = xmlDecode(_attributes[key]);
		}
		return tmp;
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	XmlNode setAttribute(string name, string value) {
		_attributes[name] = xmlEncode(value);
		return this;
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(string name, long value) {
		version(D_Version2) {
			return setAttribute(name, to!(string)(value));
		} else {
			return setAttribute(name, tostring(value));
		}
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	XmlNode setAttribute(string name, float value) {
		version(D_Version2) {
			return setAttribute(name, to!(string)(value));
		} else {
			return setAttribute(name, tostring(value));
		}
	}

	// Remove the attribute with name.
	XmlNode removeAttribute(string name) {
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
	deprecated XmlNode addCdata(string cdata) {
		return addCData(cdata);
	}

	// make an alias so as not to break compatibility
	XmlNode addCData(string cdata) {
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

	// this should be done with casting tests
	bool isXmlComment() {
		return false;
	}

	// this makes life easier for those looking to pull cdata from tags that only have that as the single subnode
	string getCData() {
		string tmp;
		foreach(child;_children) {
			tmp ~= child.toString(); 
		}
		return tmp;
	}

	protected string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<" ~ _name ~ genAttrString();

		if (_children.length == 0)
			s ~= " /"; // We want <blah /> if the node has no children.
		s ~= ">";

		return s;
	}

	protected string asCloseTag() {
		if (_name.length == 0) {
			return null;
		}
		if (_children.length != 0)
			return "</" ~ _name ~ ">";
		else
			return null; // don't need it.  Leaves close themselves via the <blah /> syntax.
	}

	protected bool isLeaf() {
		return _children.length == 0;
	}

	// this is a dump of the xml structure to a string with no newlines and no linefeeds
	override string toString() {
		auto tmp = asOpenTag();

		if (_children.length) {
			tmp ~= getCData();
			tmp ~= asCloseTag();
		}
		return tmp;
	}

	// this is a dump of the xml structure in to pretty, tabbed format
	string write(string indent=null) {
		string tmp;
		if (getName.length) tmp = indent~asOpenTag()~"\n";

		if (_children.length)
		{
			for (int i = 0; i < _children.length; i++)
			{
				// these guys are supposed to do their own indentation
				tmp ~= _children[i].write(indent~(getName.length?"	":"")); 
			}
			if (getName.length) tmp ~= indent~asCloseTag()~"\n";
		}
		return tmp;
	
	}

	// add children from a character array containing xml
	void addChildren(string xsrc) {
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

	// snag some text and lob it into a cdata node
	private void parseCData(XmlNode parent,inout string xsrc) {
		int slice;
		string token;
		slice = readUntil(xsrc,"<");
		token = strip(xsrc[0..slice]);
		xsrc = xsrc[slice..$];
		debug(xml)writefln("I found cdata text: %s",token);
		auto cd = new CData;
		cd._cdata = token;
		parent.addChild(cd);
	}

	// parse out a close tag and make sure it's the one we want
	private void parseCloseTag(XmlNode parent,inout string xsrc) {
		int slice;
		string token;
		slice = readUntil(xsrc,">");
		token = strip(xsrc[1..slice]);
		xsrc = xsrc[slice+1..$];
		debug(xml)writefln("I found a closing tag (yikes):%s!",token);
		if (token.icmp(parent.getName()) != 0) throw new XmlError("Wrong close tag: "~token);
	}

	// rip off a xml processing instruction, like the ones that come at the beginning of xml documents
	private void parseXMLPI(XmlNode parent,inout string xsrc) {
		// rip off <?
		xsrc = stripl(xsrc[1..$]);
		// rip off name
		string name = getWSToken(xsrc);
		if (name[$-1] == '?') {
			// and we're at the end of the element
			name = name[0..$-1];
			parent.addChild(new XmlPI(name));
			return;
		}
		// rip off attributes while looking for ?>
		debug(xml)writefln("Got a %s XML processing instruction",name);
		XmlPI newnode = new XmlPI(name);
		xsrc = stripl(xsrc);
		while(xsrc.length >= 2 && xsrc[0..2] != "?>") {
			parseAttribute(newnode,xsrc);
		}
		// make sure that the ?> is there and rip it off
		if (xsrc[0..2] != "?>") throw new XmlError("Could not find the end to xml processing instruction "~name);
		xsrc = xsrc[2..$];
		parent.addChild(newnode);
	}

	// rip off an unparsed character data node
	private void parseUCData(XmlNode parent,inout string xsrc) {
		int slice;
		string token;
		xsrc = xsrc[7..$];
		slice = readUntil(xsrc,"]]>");
		token = xsrc[0..slice];
		xsrc = xsrc[slice+3..$];
		debug(xml)writefln("I found cdata text: %s",token);
		auto cd = new CData;
		cd._cdata = token;
		parent.addChild(cd);
	}

	// rip off a comment
	private void parseComment(XmlNode parent,inout string xsrc) {
		int slice;
		string token;
		xsrc = xsrc[2..$];
		slice = readUntil(xsrc,"-->");
		token = xsrc[0..slice];
		xsrc = xsrc[slice+3..$];
		token = strip(token);
		parent.addChild(new XmlComment(token));
	}

	// rip off a XML Instruction
	private void parseXMLInst(XmlNode parent,inout string xsrc) {
		int slice;
		string token;
		slice = readUntil(xsrc,">");
		slice += ">".length;
		if (slice>xsrc.length) slice = xsrc.length;
		token = xsrc[0..slice];
		xsrc = xsrc[slice..$];
		// XXX we probably want to do something with these
	}

	// rip off a XML Instruction
	private void parseOpenTag(XmlNode parent,inout string xsrc) {
		// rip off name
		string name = getWSToken(xsrc);
		// rip off attributes while looking for ?>
		debug(xml)writefln("Got a %s XML processing instruction",name);
		XmlNode newnode = new XmlNode(name);
		xsrc = stripl(xsrc);
		while(xsrc.length && xsrc[0] != '/' && xsrc[0] != '>') {
			parseAttribute(newnode,xsrc);
		}
		// check for self-closing tag
		parent.addChild(newnode);
		if (xsrc[0] == '/') {
			// strip off the / and go about business as normal
			xsrc = stripl(xsrc[1..$]);
			// check for >
			if (!xsrc.length || xsrc[0] != '>') throw new XmlError("Unable to find end of "~name~" tag");
			xsrc = stripl(xsrc[1..$]);
			debug(xml)writefln("self-closing tag!");
			return;
		} 
		// check for >
		if (!xsrc.length || xsrc[0] != '>') throw new XmlError("Unable to find end of "~name~" tag");
		xsrc = stripl(xsrc[1..$]);
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

	// returns everything after the first node TREE (a node can be text as well)
	private int parseNode(XmlNode parent,inout string xsrc) {
		// if it was just whitespace and no more text or tags, make sure that's covered
		int ret = 0;
		xsrc = stripl(xsrc);
		debug(xml)writefln("Parsing text: %s",xsrc);
		if (!xsrc.length) {
			return 0;
		}
		string token;
		if (xsrc[0] != '<') {
			parseCData(parent,xsrc);
			return 0;
		} 
		xsrc = xsrc[1..$];
		
		// types of tags, gotta make sure we find the closing > (or ]]> in the case of ucdata)
		switch(xsrc[0]) {
		case '/':
			// closing tag!
			parseCloseTag(parent,xsrc);
			ret = 1;
			break;
		case '?':
			// processing instruction!
			parseXMLPI(parent,xsrc);
			break;
		case '!':
			xsrc = stripl(xsrc[1..$]);
			// 10 is the magic number that allows for the empty cdata string [CDATA[]]>
			if (xsrc.length >= 10 && xsrc[0..7].cmp("[CDATA[") == 0) {
				// unparsed cdata!
				parseUCData(parent,xsrc);
				break;
			// make sure we parse out comments, minimum length for this is 7 (<!---->)
			} else if (xsrc.length >= 5 && xsrc[0..2].cmp("--") == 0) {
				parseComment(parent,xsrc);
				break;
			}
			// xml instruction is the default for this case
			parseXMLInst(parent,xsrc);
			break;
		default:
			// just a regular old tag
			parseOpenTag(parent,xsrc);
			break;
		}
		return ret;
	}

	// read data until the delimiter is found, return the index where the delimiter starts
	private int readUntil(string xsrc, string delim) {
		// the -delim.length is partially optimization and partially avoiding jumping the array bounds
		int i = xsrc.find(delim);
		// yeah...if we didn't find it, then the whole string is the token :D
		if (i == -1) {
			return xsrc.length;
		}
		return i;
	}

	// basically to get the name off of open tags
	private string getWSToken(inout string input) {
		input = stripl(input);
		int i;
		for(i=0;i<input.length && !isspace(input[i]) && input[i] != '>';i++){}
		auto ret = input[0..i];
		input = input[i..$];
		return ret;
	}

	// this code is now officially prettified
	private void parseAttribute (XmlNode xml,inout string attrstr,string term = null) {
		string ripName(inout string input) {
			int i;
			for(i=0;i < input.length && !isspace(input[i]) && input[i] != '=';i++){}
			auto ret = input[0..i];
			input = input[i..$];
			return ret;
		}
		string ripValue(inout string input) {
		        int x;
			char quot = input[0];
			// rip off the starting quote
		        input = input[1..$];
			// find the end of the string we want
		        for(x = 0;(input[x] != quot || (input[x] == quot && x && input[x-1] == '\\')) && x < input.length;x++) {
		        }
		        string tmp = input[0..x];
			// add one to leave off the quote
		        input = input[x+1..$];
		        return tmp;
		}

		// snag the name from the attribute string
		string value,name = ripName(attrstr);
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
		debug(xml)writefln("Got attr %s and value \"%s\"",name,value);
		xml._attributes[name] = value;
		attrstr = stripl(attrstr);
	}

	XmlNode[]parseXPath(string xpath,bool caseSensitive = false) {
		// rip off the leading / if it's there and we're not looking for a deep path
		if (!isDeepPath(xpath) && xpath.length && xpath[0] == '/') xpath = xpath[1..$];
		debug(xpath) writefln("Got xpath %s in node %s",xpath,getName);
		string truncxpath;
		auto nextnode = getNextNode(xpath,truncxpath);
		string attrmatch;
		// need to be able to split the attribute match off even when it doesn't have [] around it
		int offset = nextnode.find("[");
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
		} else foreach(child;getChildren) if (!child.isCData && !child.isXmlComment && !child.isXmlPI && child.matchXPathAttr(attrmatch,caseSensitive)) {
			if (!nextnode.length || (caseSensitive && child.getName == nextnode) || (!caseSensitive && !child.getName().icmp(nextnode))) {
				// child that matches the search string, pass on the truncated string
				debug(xpath) writefln("Sending %s to %s",truncxpath,child.getName);
				retarr ~= child.parseXPath(truncxpath,caseSensitive);
			}
		}
		// we aren't on us, but check to see if we're looking for a deep path, and delve in accordingly
		// currently this means, the entire tree could be traversed multiple times for a single query...eww
		// and the query // should generate a list of the entire tree, in the order the elements specifically appear
		if (isDeepPath(xpath)) foreach(child;getChildren) if (!child.isCData && !child.isXmlComment && !child.isXmlPI) {
			// throw the exact same xpath at each child
			retarr ~= child.parseXPath(xpath,caseSensitive);
		}
		return retarr;
	}

	private bool matchXPathAttr(string attrstr,bool caseSen) {
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
		string[]attrlist = attrstr.split(" and ");
		foreach(attr;attrlist) {
			debug(xpath)writefln("matching on %s",attr);
			string datamatch;
			int sep = attr.find("=");
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
	
	private bool isDeepPath(string xpath) {
		// check to see if we're currently searching a deep path
		if (xpath.length > 1 && xpath[0] == '/' && xpath[1] == '/') {
			return true;
		}
		return false;
	}

	// this does not modify the incoming string, only pulls a slice out of it
	private string getNextNode(string xpath,out string truncxpath) {
		if (isDeepPath(xpath)) xpath = xpath[2..$];
		string[]nodes = split(xpath,"/");
		if (nodes.length) {
			// leading slashes will be removed in recursive calls 
			if (nodes.length > 1) truncxpath = xpath[nodes[0].length..$];
			return nodes[0];
		}
		// i'm not sure this can occur unless the string was blank to begin with...
		truncxpath = null;
		return null;
	}

	// opIndex accessors
	string opIndex(string attr) {
		return getAttribute(attr);
	}

	XmlNode opIndex(int childnum) {
		if (childnum < _children.length) return _children[childnum];
		return null;
	}

	XmlNode opIndexAssign(string value,string name) {
		return setAttribute(name,value);
	}

	XmlNode opIndexAssign(XmlNode x,int childnum) {
		if (childnum > _children.length) throw new Exception("Child element assignment is outside of array bounds");
		_children[childnum] = x;
		return this;
	}
}

// class specializations for different types of nodes, such as cdata and instructions
// A node type for CData.
class CData : XmlNode
{
	private string _cdata;

	// assumes data is coming from a user program, possibly with unescaped data
	this(string cdata) {
		setCData(cdata);
	}

	this(){}

	override bool isCData() {
		return true;
	}

	// this is for user programs and returns unescaped data
	override string getCData() {
		return xmlDecode(_cdata);
	}

	// assumes data is coming from a user program, possibly with unescaped data
	CData setCData(string cdata) {
		_cdata = xmlEncode(cdata);
		return this;
	}

	// the following two functions assume that data is going out to real xml, and so it should be escaped
	protected override string toString() {
		return _cdata;
	}

	protected override string write(string indent) {
		return indent~toString()~"\n";
	}

	protected override string asCloseTag() { return null; }

	protected override bool isLeaf() {
		return true;
	}

	override string getName() {
		throw new XmlError("CData nodes do not have names to get.");
	}

	// Set the name of this XmlNode.
	override void setName(string newName) {
		throw new XmlError("CData nodes do not have names to set.");
	}

	// Does this XmlNode have an attribute with name?
	override bool hasAttribute(string name) {
		throw new XmlError("CData nodes do not have attributes.");
	}

	// Get the attribute with name, or return null if no attribute has that name.
	override string getAttribute(string name) {
		throw new XmlError("CData nodes do not have attributes to get.");
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	override string[string] getAttributes() {
		throw new XmlError("CData nodes do not have attributes to get.");
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	override XmlNode setAttribute(string name, string value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(string name, long value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(string name, float value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to CData.");
	}

	// Add a child Node of cdata (text).
	deprecated override XmlNode addCdata(string cdata) {
		throw new XmlError("Cannot add a child node to CData.");
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(string cdata) {
		throw new XmlError("Cannot add a child node to CData.");
	}
}

// A node type for xml instructions.
class XmlPI : XmlNode {
	this(string name) {
		super(name);
	}

	override bool isXmlPI() {
		return true;
	}

	override string getCData() {
		return null;
	}
	override string toString() {
		return asOpenTag();
	}

	protected override string write(string indent=null) {
		return indent~asOpenTag()~"\n";
	}
	protected override string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<?" ~ _name ~ genAttrString() ~ "?>";
		return s;
	}

	protected override string asCloseTag() { return null; }

	protected override bool isLeaf() {
		return true;
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to XmlPI.");
	}

	// Add a child Node of cdata (text).
	deprecated override XmlNode addCdata(string cdata) {
		throw new XmlError("Cannot add a child node to XmlPI.");
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(string cdata) {
		throw new XmlError("Cannot add a child node to XmlPI.");
	}
}

// A node type for xml instructions.
class XmlComment : XmlNode {
	string comment;
	this(string incomment) {
		comment = incomment;
		super(null);
	}

	override bool isXmlComment() {
		return true;
	}

	override string getCData() {
		return null;
	}
	override string toString() {
		return asOpenTag();
	}

	protected override string write(string indent=null) {
		return indent~asOpenTag()~"\n";
	}
	protected override string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<!--" ~ comment  ~ "-->";
		return s;
	}

	protected override string asCloseTag() { return null; }

	protected override bool isLeaf() {
		return true;
	}

	override string getName() {
		throw new XmlError("Comment nodes do not have names to get.");
	}

	// Set the name of this XmlNode.
	override void setName(string newName) {
		throw new XmlError("Comment nodes do not have names to set.");
	}

	// Does this XmlNode have an attribute with name?
	override bool hasAttribute(string name) {
		throw new XmlError("Comment nodes do not have attributes.");
	}

	// Get the attribute with name, or return null if no attribute has that name.
	override string getAttribute(string name) {
		throw new XmlError("Comment nodes do not have attributes to get.");
	}

	// Return an array of all attributes (by reference, no copy is made).
	// the user should know that these may have html escapes
	override string[string] getAttributes() {
		throw new XmlError("Comment nodes do not have attributes to get.");
	}

	/**
	 * Set an attribute to a string value.  The attribute is created if it
	 * doesn't exist.*/
	override XmlNode setAttribute(string name, string value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	/**
	 * Set an attribute to an integer value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(string name, long value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	/**
	 * Set an attribute to a float value (stored internally as a string).
	 * The attribute is created if it doesn't exist.*/
	override XmlNode setAttribute(string name, float value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	// Add an XmlNode child.
	override XmlNode addChild(XmlNode newNode) {
		throw new XmlError("Cannot add a child node to comment.");
	}

	// Add a child Node of cdata (text).
	deprecated override XmlNode addCdata(string cdata) {
		throw new XmlError("Cannot add a child node to comment.");
	}

	// make an alias so as not to break compatibility
	override XmlNode addCData(string cdata) {
		throw new XmlError("Cannot add a child node to comment.");
	}
}


/// Encode characters such as &, <, >, etc. as their xml/html equivalents
string xmlEncode(string src) {
	string tempStr;
        tempStr = replace(src    , "&", "&amp;");
        tempStr = replace(tempStr, "<", "&lt;");
        tempStr = replace(tempStr, ">", "&gt;");
        tempStr = replace(tempStr, "\"", "&quot;");
        tempStr = replace(tempStr, "'", "&apos;");
        return tempStr;
}

/// Convert xml-encoded special characters such as &amp;amp; back to &amp;.
string xmlDecode(string src) {
	string tempStr;
        tempStr = replace(src    , "&lt;",  "<");
        tempStr = replace(tempStr, "&gt;",  ">");
        tempStr = replace(tempStr, "&quot;",  "\"");
        tempStr = replace(tempStr, "&amp;", "&");
        tempStr = replace(tempStr, "&apos;", "'");
	// take care of decimal character entities
	tempStr = std.regexp.sub(tempStr,"&#\\d{1,8};",(RegExp m) {
		auto cnum = m.match(0)[2..$-1];
		version(D_Version2) {
			dchar dnum = cast(dchar)to!(int)(cnum);
		} else {
			dchar dnum = cast(dchar)atoi(cnum);
		}
		return toUTF8([dnum]);
	},"g");
	// take care of hex character entities
	tempStr = std.regexp.sub(tempStr,"&#[xX][0-9a-fA-F]{1,8};",(RegExp m) {
		auto cnum = m.match(0)[3..$-1];
		dchar dnum = hex2dchar(cnum[1..$]);
		return toUTF8([dnum]);
	},"g");
        return tempStr;
}

dchar hex2dchar (string hex) {
	dchar res;
	foreach(digit;hex) {
		res <<= 4;
		res |= toHVal(digit);
	}
	return res;
}

dchar toHVal(char digit) {
	if (digit >= '0' && digit <= '9') {
		return digit-'0';
	}
	if (digit >= 'a' && digit <= 'f') {
		return digit-'a';
	}
	if (digit >= 'A' && digit <= 'F') {
		return digit-'A';
	}
	return 0;
}

unittest {
	string xmlstring = "<message responseID=\"1234abcd\" text=\"weather 12345\" type=\"message\"><flags>triggered</flags><flags>targeted</flags></message>";
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

