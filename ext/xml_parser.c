#include <ruby.h>

static VALUE cXml;
static VALUE cTag;
static VALUE cCmt;
static ID id_new;
static ID id_set_uniq;
static ID id_entities_decode;
static ID id_aset;


static VALUE rbxml_parse_element( VALUE self )
{
	static const char wstagname[]  = " \r\t\n/>";
	static const char spacewhite[] = " \r\t";

	VALUE str_value = rb_iv_get( self, "@str" );
	if ( TYPE(str_value) != T_STRING )
		return Qnil;

	char *str = RSTRING_PTR( str_value );
	unsigned long str_len = RSTRING_LEN( str_value );
	unsigned long off = rb_num2ulong( rb_iv_get( self, "@off" ) );
	unsigned long lineno = rb_num2ulong( rb_iv_get( self, "@lineno" ) );
	unsigned long off_start;

	VALUE ret;

#define do_raise(fmt...) \
do { \
	rb_iv_set( self, "@off", rb_uint2inum( off ) ); \
	rb_iv_set( self, "@lineno", rb_uint2inum( lineno ) ); \
	char errmsg[255]; \
	snprintf( errmsg, sizeof(errmsg), ##fmt ); \
	VALUE av[2] = { self, rb_str_new2( errmsg ) }; \
	rb_exc_raise( rb_make_exception( 2, av ) ); \
} while (0)

#define skipspaces() \
do { \
	for (;;) { \
		off += strspn( str + off, spacewhite ); \
		if ( str[off] != '\n' ) \
			break; \
		++lineno; \
		++off; \
	} \
} while (0)

	if ( str[off] == '<' )
	{
		/* <stuff */

		off++;
		skipspaces();

		/* tag name */
		off_start = off;
		if ( str[off] == '/' )
			++off;
		off += strcspn( str + off, wstagname );

		if ( str[off_start] == '!' && str[off_start + 1] == '-' && str[off_start + 2] == '-' )
		{
			/* <!-- comment --> */
			off_start += 3;

			for (;;) {
				/* scan for end tag, but keep lineno up to date */
				off += strcspn( str + off, "\n>" );
				if ( str[off] == '\n' ) {
					++off;
					++lineno;
				} else if ( str[off] == '>' ) {
					++off;
					if ( off > off_start + 3 && str[off - 2] == '-' && str[off - 3] == '-' )
						break;
				} else
					break;
			}

			/* ret = ::Xml::Comment.new(cmt) */
			unsigned long off_end = off; /* off may be EOF */
			if ( str[off_end - 1] == '>' && str[off_end - 2] == '-' && str[off_end - 3] )
				off_end -= 3;

			ret = rb_funcall( cCmt, id_new, 1, rb_str_new( str + off_start, off_end - off_start ) );
		}
		else
		{
			/* ret = ::Xml::Tag.new(tagname) */
			ret = rb_funcall( cTag, id_new, 1, rb_str_new( str + off_start, off - off_start ) );

			while ( off < str_len && str[off] != '>' ) {
				/* parse attributes */
				skipspaces();

				switch ( str[off] )
				{
				case '>':
					break;

				case '/':
					/* <foo /> */
					++off;
					skipspaces();
					if ( str[off] != '>' )
						do_raise( "expected /> in <%s", RSTRING_PTR( rb_iv_get( ret, "@name" ) ) );
					rb_funcall( ret, id_set_uniq, 0 );
					break;

				case '?':
					if ( RSTRING_PTR( rb_iv_get( ret, "@name" ) )[0] != '?' )
						do_raise( "invalid ? in <%s", RSTRING_PTR( rb_iv_get( ret, "@name" ) ) );
					++off;
					break;

				case 'a' ... 'z':
				case 'A' ... 'Z':
					/* <foo a="b" > */
					off_start = off;
					while ( off < str_len && (
							( str[off] >= 'a' && str[off] <= 'z' ) ||
							( str[off] >= 'A' && str[off] <= 'Z' ) ||
							( str[off] >= '0' && str[off] <= '9' ) ||
							str[off] == '_' ||
							str[off] == '$' ||
							str[off] == ':' ||
							str[off] == '.' ||
							str[off] == '-'
							) )
						++off;

					VALUE attrname = rb_str_new( str + off_start, off - off_start );
					VALUE attrvalue = attrname;
					skipspaces();

					if ( str[off] == '=' ) {
						++off;
						skipspaces();

						if ( str[off] == '"' || str[off] == '\'' )
						{
							char sep = str[off];
							++off;
							off_start = off;
							while ( off < str_len && str[off] != sep )
							{
								if ( str[off] == '\n' )
									++lineno;
								++off;
							}

							if ( str[off] != sep )
								do_raise( "unclosed quote in <%s %s=", RSTRING_PTR( rb_iv_get( ret, "@name" ) ), RSTRING_PTR( attrname ) );

							attrvalue = rb_str_new( str + off_start, off - off_start );

							++off;
						}
						else
						{
							off_start = off;
							off += strcspn( str + off, wstagname );
							attrvalue = rb_str_new( str + off_start, off - off_start );
						}
					}

					/* tag[attrname] = Xml.entities_decode(attrvalue) */
					attrvalue = rb_funcall( cXml, id_entities_decode, 1, attrvalue );
					rb_funcall( ret, id_aset, 2, attrname, attrvalue );
					break;

				default:
					do_raise( "invalid attribute for <%s", RSTRING_PTR( rb_iv_get( ret, "@name" ) ) );
				}
			}

			if ( str[off] != '>' )
				do_raise( "unclosed tag <%s", RSTRING_PTR( rb_iv_get( ret, "@name" ) ) );
			++off;
		}
	}
	else
	{
		/* raw string */
		off_start = off;
		for (;;) {
			/* search for next tag start, keep lineno up to date */
			off += strcspn( str + off, "\n<" );
			if ( str[off] != '\n' )
				break;
			lineno += 1;
			off += 1;
		}
		ret = rb_str_new( str + off_start, off - off_start );
		/* ret = ::Xml.entities_decode(ret) */
		ret = rb_funcall( cXml, id_entities_decode, 1, ret );
	}

	rb_iv_set( self, "@off", rb_uint2inum( off ) );
	rb_iv_set( self, "@lineno", rb_uint2inum( lineno ) );

	return ret;
}

/* ruby setup */
void Init_xml_parser(void)
{
	cXml = rb_const_get( rb_cObject, rb_intern( "Xml" ) );
	cTag = rb_const_get( cXml, rb_intern( "Tag" ) );
	cCmt = rb_const_get( cXml, rb_intern( "Comment" ) );
	id_new = rb_intern( "new" );
	id_set_uniq = rb_intern( "set_uniq" );
	id_entities_decode = rb_intern( "entities_decode" );
	id_aset = rb_intern( "[]=" );
	rb_define_method( rb_const_get( cXml, rb_intern( "Parser" ) ), "parse_element", rbxml_parse_element, 0 );
}
