# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Normalize SMathML's HTML serialization to XML for Grove's SXML reader."""

from html.parser import HTMLParser
from xml.sax.saxutils import escape, quoteattr
import sys


class XmlHtmlParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)

    def handle_starttag(self, tag, attrs):
        sys.stdout.write("<" + tag)
        for name, value in attrs:
            sys.stdout.write(" " + name + "=" + quoteattr(value or ""))
        sys.stdout.write(">")

    def handle_startendtag(self, tag, attrs):
        sys.stdout.write("<" + tag)
        for name, value in attrs:
            sys.stdout.write(" " + name + "=" + quoteattr(value or ""))
        sys.stdout.write("/>")

    def handle_endtag(self, tag):
        sys.stdout.write("</" + tag + ">")

    def handle_data(self, data):
        sys.stdout.write(escape(data))

    def handle_entityref(self, name):
        from html import unescape

        sys.stdout.write(escape(unescape("&" + name + ";")))

    def handle_charref(self, name):
        from html import unescape

        sys.stdout.write(escape(unescape("&#" + name + ";")))

    def handle_decl(self, decl):
        return

    def unknown_decl(self, data):
        return

    def handle_comment(self, data):
        return


parser = XmlHtmlParser()
with open(sys.argv[1], encoding="utf-8") as source:
    parser.feed(source.read())
parser.close()
