Unified Parser
--------------
Code that defines sections (aka "pseudo-csets") and a parser that
works with them. The parser is "unified" in the sense that parsing
is done in three related forms:

* MST/MPG (Maximum Spanning Tree, Maximal Planar Graph) parsing,
  which works with a dictionary of word pairs, each word pair having
  an MI value on it. A spanning tree/graph is created, maximizing the
  total MI for the parse.

* LG parsing, with works with a dictionary of Sections, understood to
  correspond to classic LG disjuncts. This enables classic LG parsing.

* Mixed parsing, which mixes both disjunct-style and word-pair-style
  parsing. Disjuncts are used preferentially, unless they are low
  quality or are simply not available to complete the parse. These are
  supplemented with optional connectors, carrying the word-pair MI as
  the cost.

For all three cases, the final parse is chopped back up into sections,
and the counts on those Sections are updated. The parsing is "unified"
in the sense that the default is the mixed-mode, and the first two forms
take place if the dictionary definition limits the form, or if the
dictionary does not contain the data.

The goal here is to allow pair counting and more general parsing to be
intermixed in an ongoing process.

* __pseudo-csets.scm__  -- Provides a matrix API to the Sections. Rows
                           (left index) are words, columns (right index)
                           are connector sequences (pseudo-csets.)
* __lg-parser.scm__     -- Generic, mixed-mode parser.

* __sliding-block.scm__ -- Define a function that takes a large (huge)
                           text string block, and scans it with a rather
                           smaller sliding window.

###TODO
The parser currently increments counts by 1.0 for each observed section,
but perhaps the weighting should be some function of the MI. If we
really, truly believe the MI, then the weighting should be 2^-MI, and
we should look at as many parses as needed until this gets "negligible".
Hmm. This begs a question: does this ever get negligible?
