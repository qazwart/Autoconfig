# NAME

autoconfig.pl

# SYNOPSIS

     autoconfig.pl [ -answers <answer_file> ] [ -suffix <template_suffix> ] \
	[ -test (all|templates) ] [ -defaults ] \
	[ -directory dir1 -directory dir2... ] [ helpstring <help_string> ]

or
    autoconfig.pl -help
or
    autoconfig.pl --options

# DESCRPTION

This program looks for i<Template Files>, and turns those template files
into the required configuration files. It does this by looking for _questions_
in these template files, finding the answers to these questions, and filling
in the macros with the correct answer. It then will generate an _answer file_,
so the next time the configuration needs to be reexecuted, it won't have to reask
the questions.



# OPTIONS

- \-answers

    The name of the answer file in _Answer File Format_. The answer file is really nothing more
    than a bunch of optional comment lines that start with "\#" and a line with the _macro name_ and the
    value of that macro. For example:

         # This is a comment
         # Here's another comment
         MY_MACRO = The macro's value

    In the above, the macro _MY\_MACRO_ is being set to the string _The
    macro's value_. This makes it easy to create a fresh answer file, or to
    edit an existing one. When this program is executed, the answer file
    will be rewritten with any newly answered macros, and the comments will
    be changed to reflect the name of the template file that contained the
    macro, and the line number of that started the definition, and other
    information. This makes it easy to see what the _question_ was and
    which template file it was located in. For example, the above might get
    rewritten as:

        # MACRO: MY_MACRO STRING
        # File: ./foo/bar/some.template:23
        # Q: What is the value of your Macro?
        

        MY_MACRO = The macro's value

    The default Answer file is called `autoconfig.answers`

- \-test

    A test run of the program. This can be used to test whether the
    templates are valid and if all answers from the answer files were given,
    and there are no unknown answers. Valid arguments are `all` for both
    the templates and answers, or `templates` for just the templates.

- \-suffix

    The suffix for the various template files. The default will be
    _.template_. When a template file is processed, the name of the
    configuration file is the template name minus the suffix. For example,
    `config.properties.template` will become `config.properties` in the
    same folder where `config.properties.template` was located.

- \-defaults 

    If a _Question_ has a default answer, assume that the answer is the
    default value, and don't ask the question. Default is to ask the
    question for macros with no answer whether or not there is a default
    answer.  =item -directory

- \-directory

    This is the directory tree to search for template files. All files in
    this directory tree with the given template suffix will be parsed and
    turned into regular configuration files. This parameter my be repeated
    as many times as needed.

    The default is the current directory and will search all subdirectories
    under the current directory.

- \-helpstring

    This is what the user can type to get further help on a question. The
    default is _HELP!_.

- \-help

    Displays the synopsis section of this document

- \-options

    Displays the synopsis section and the option section to describe those
    options.

# TEMPLATE FILES

Template files look just like the configuration files they are for
except they contain the macro names in the place of the actual value of
the parameter. Imagine a regular Java properties file called
`config.properties.` The template file would be called
`config.properties.template` and would look like this:

     # User Inforamtion

     mailto = %MAIL_TO%
     name = %USER_NAME%
     phone = %PHONE%
     office=%OFFICE_NUMBER%
     employment_date=%EMPLOYMENT_DATE%
     company = First National VegiBank, N.A.

Macro names are surrounded by percent signs and are replaced by the
actual values. These could already be in an Answer file, so when the
program runs, it merely replaces the macros with their actual values.

If that's all this did, it wouldn't do much more than Ant does when it
copies and filters files. However, the fun comes when a macro does not
already have an answer.  In that case, this program will actually ask
the user a question, verify the answer, and save the answer the next
time this runs.

This does several things. First of all, it makes the template files (and
the resulting configuration files) self documenting. What does a
particular value represent? You can look at the question. Second of all,
if a new parameter is added to a configuration, the user who is
installing the software is given a warning. If that user knows the
answer, they could simply supply it and go on. If the user does not
know the answer, they can at least alert the developer that there is
an issue with the installation.

You do this by defining a _macro_. Macro definitions are made to look
like comments, so they don't affect the actual configuration files.
Macro lines can either start with a `#` or double `//`, so they can
look like a Properties file comment. If you are placing this inside an
XML file, you can define a macro by putting the <!-- on the\\ line
before the macro definition and a --> after the line. That way, the
macro definition is enveloped in comments.

Macro definitions follow a simple format. For example, to define
`%USER_NAME%` in the above, the macro definition would look something
like this:

    # MACRO: USER_NAME
    # Q: What is the name of the user?

And that's pretty much it. A macro definition needs a macro name and a
question which is simply a line that starts with a comment and a `Q:`.
Macros can also contain a `macro type`, so the above definition could
look like this too:

    # MACRO: USER_NAME STRING
    # Q: What is the name of the user?

The macro type (`STRING` in this case) is the second parameter on the
`# MACRO:` line. If a macro type isn't given, it is assumed to be a
macro type of string.

If you specify that the Macro type is either `STRING` or `WORDS`, you
can specify that the user could leave this as a blank value by
specifying `NULL` or `NULL_OK` after the type parameter.

    # MACRO PASSWORD STRING NULL_OK
    # Q: What is your password?

The following are all of the valid Macro types:

- STRING

    The answer needs to be a string of some sort. Strings are case
    sensitive.

- WORDS

    The answer needs to be words. Words are just like strings, but they're
    not case sensitive. This comes in handy when you force the answer to be
    in a particular range. You can also force the answer to be upper case,
    lower case, or where the first word is capitalized.

- NUMBER

    The answer needs to be a valid number. A number is defined by the
    _looks\_like\_number_ function from the Scalar::Util module.

- INTEGER

    The answer must be an integer.

- DATE

    The answer must be a date or time string. Dates must have a defined
    _Format_, so that the answer can be verified against that format.

- REGEX

    The answer must match the regular expression given by its _Format_.

- CHOICE

    The answer must be one of the choices give.

- IPADDR

    The answer must be a valid IPv4 IP address.

- DEFAULT

    Default type macros don't ask questions, but simply provide a default as
    given if there is not already an answer. This is a good way to provide a
    particular value for a parameter, but allow sites to be able to modify
    it in their answer files.

## OTHER MACRO PARAMETERS

All macros have the following parameters. The only required parameters
are the Macro definition heading, and at least one _Question_ line.

- \# MACRO:

    This is the _macro_ definition line. The line takes one or two
    paramters. The first parameter is the name of the macro (which must
    consist of letters, numbers, and underscores only). The second parameter
    is the macro type. Macro names are case insensitive, and so are macro
    types. These lines are all equivelent:

         # macro: user_name string
         # Macro: User_name String
         # MACRO: USER_NAME STRING

    This starts a Macro definition. The macro definition ends when a
    non-comment line is detected, or another macro definition line is
    detected.

- \# Q:

    This line is the question to ask about the macro's value. There can be
    multiple question lines.  Each question line will appear on its own
    line, so you can format the question easier.

- \# H:

    This is the help line. This allows you to provide further information
    when a user requests help, or if the user gives an invalid answer. This
    makes it easy to ask a brief question (What is the server name?), and
    then provide more details in the help statement (the following are our
    current servers...). Liek the question parameter, the help parameter can
    also be multiple lines.

- \# D:

    The default value. This is the answer to use if the user simply presses
    <RETURN>. It is also the answer if the user uses the
    `-defaults` parameter when the program was executed.

- \# RANGE:

    This defines a from and two range for the answer. There should be two
    values on this line and they can be separated by an optional dash. For
    example:

        # MACRO: PICK_A_NUMBER INTEGER
        # RANGE: 1 - 100
        # Q: Pick a number between 1 to 100!

    You may also leave out the dash:

        # MACRO: PICK_A_NUMBER INTEGER
        # RANGE: 1 100
        # Q: Pick a number between 1 to 100!

    The program will give you an error if your range does not match the
    macro type, or if your _to_ value is less than the _from_ value.

    If the macro type is _Words_, the from values are case insensitive.

- \# FROM:

    Defines the lowest possible answer permitted. If the macro type is
    _Words_, the from value is case insensitive.

    The program will give you an error if your range does not match the
    macro type, or if your _to_ value is less than the _from_ value.

- \# TO:

    Defines the highest possible answer permitted.  If the macro type is
    _Words_, the from value is case insensitive.

    The program will give you an error if your range does not match the
    macro type, or if your _to_ value is less than the _from_ value.

## OTHER PARAMETERS

Some macros types take other possible parameters:

- DATE

    Dates can take a possible _Format_ parameter. This parameter is the
    format of the date that you expect. Dates can contain any number of date
    or time parameters. The answer given must match the format, or the
    answer will be rejected. Dates can contain the following special
    charcters:

    - Y

        Year

    - M

        Month

    - D

        Day of the Month

    - h

        Hour

    - m

        Minute

    - s

        Second

    - A

        AM/PM Meridian marker. Must be uppercase

    - a

        AM/PM Meridian marker. Must be lowercase

    All other characters in the date format must match exactly as written.
    Here's an example of a _Date_ macro definition:

        # MACRO: START_DATE DATE
        # FORMAT: YYYY-MM-DD
        # Q: Default start date for reports

    In this case, the date is expected to have a four character year, and a
    2 character month and day separated by dashes. For example:

    - 2001-01-15

        Valid

    - 20010115

        Invalid

    - 2001/01/15

        Invalid

    You can also do time definitions too:

        # MACRO: EXECUTE_CLEANUP DATE
        # FORMAT: hh:mm
        # Q: At what time should the clean up routine run?

    In this case, you are only expecting an hour and minute for the time.
    Since the `A` format character isn't specified, this will be a 24 hour
    time. The following is a 12 hour time:

        # MACRO: EXECUTE_CLEANUP DATE
        # FORMAT: hh:mmA
        # Q: At what time should the clean up routine run?

    In this case, the time would be something like `11:45A`. If you double
    up the `A` character, the format would be something like this:

        # MACRO: EXECUTE_CLEANUP DATE
        # FORMAT: hh:mmAA
        # Q: At what time should the clean up routine run?

    In this case, the time would be something like `11:45AM`.

- REGEX

    Regular expressions also take a _Format_ parameter. However, this is
    the regular expression that the answer must match. For example:

        # MACRO: PHONE_NUMBER REGEX
        # FORMAT: \d{3,3}-\d(3,3}-\d{4,4}
        # Q: What is the phone number (including the area code)?

- WORDS

    Macros of type _Words_ can take a _Force_ parameter. This parameter
    tells you whether to force the answer to be uppercase, lowercase, or
    capital case. The user does not need to put the macro in this case, the
    answer will simply be forced into that case. For example:

        # Macro: USER_ID WORDS
        # FORCE: UC
        # Q: User Name?

    In this case, the `USER_ID` will always be upper case if the user
    entered in `David`, the answer will be `DAVID`. The force macro can
    take the following values:

    - UC

        Force answer to uppercase.

    - LC

        Force answer to lowercase.

    - UCFIRST

        Force answer to capitalize only the first character of the answer.

## The CHOICE Macro

The Choice macro is a bit different from the other macros. This will
give the user a selection of choices they can choose. This macro does
not take a range (the range is the range of choices), or a _From_ or a
_To_ parameter. If a default is given, it is the number of the choice
to select.

Choice parameters start with a `# C:` and contain a description to
display, and an actual value to use for a particular answer. For
example:

    # MACRO CACHE_SIZE CHOICE
    # Q: How big should the cache be?
    # C: Tiny:2
    # C: Small:5
    # C: Medium:10
    # C: Big:30
    # C: Huge:50
    # C: Tremendous:1000

In the above, the user will be asked the size of the pool, and be given
six choices:

     How big should the cache be?
     1). Tiny
     2). Small
     3). Medium
     4). Huge
     5). Tremendous

     Answer: 

If the user selects _3_, the `CACHE_SIZE` macro will be set to `10`.
Each choice line contains a description followed by a colon followed by
a value that will be used.

Descriptions cannot contain colons, but values may. For example:

     # Macro: MAC_ADDRESS
     # Q: Which Mac Address should be searched for:
     # C: Office Printer:D4:BE:D9:11:29:66
     # C: Debbie's Computer:24:77:03:38:52:AC

     The values in the above example contain colons.

Also note that choices can be null too:

     # Macro: Password Choice
     # Q: What Type of Password would you like?
     # C: Really complex and hard to remember:123j12k3u=dqd1y398129731ho1dasksn
     # C: Easier to remember, but strong:the-quot-flob-mober-3
     # C: Easy to remember: swordfish
     # C: None:

# SPECIAL MACRO NAMES

There are two sets of special macro names. These are not set by macro
questions, but by the environmet.

## \_ENV\_ Macros

The `_ENV_` macros start with the string `_ENV_` and the name of the
environment variable is appended to the end of the macro name. There is
one of these special `_ENV_` macros for each environment variable in
your system. Case is insignificant, so if you have `PATH` and `path`
as two environment variables, only one will be `_ENV_PATH`, but we
cannot say which one would be used.

This allows you to use environment variables in your Macros.

## \_SP\_ Macros

There are some _special_ macro values that are automatically generated.
These include:

- `_SP_HOSTNAME`: The hostname of the system (may include domain
name).
- `_SP_SHORTHOSTNAME_`: The hostname of the system minus any
domain name information (everything after the first `.` is stripped
off).

# ETCETRICITIES

Included in this project is a sample template. Use this to explore this program.

## XML HTML File Handling

This program allows for XML file handling if you take certain
precautions. This mainly has to do with the way that the IF/ENDIF
process works.

You need to surround the all macro definition lines and IF/ENDIF lines
with comment marks, and everything should be just fine. For example:

     <!--
     #  Macro: server_flag choice
     #  Q: Is this a server?
     #  C: Yes:TRUE
     #  C: No:FALSE
     -->

     <!--
     # IF: NOT SERVER_FLAG = TRUE
     -->

     <!--
     # Macro: SERVER_ID String
     # Q: What's the Server ID?
     -->

     <!--
     # ENDIF:
     -->

     <!--
     # Macro: password string
     # Q: What is the user password?
     -->

     <password>%PASSWORD%</password>

In the above example, this program will remove any stand alone XML
comment markers if the user said that this is NOT a server. This should
allow the XML to remain valid.  If the user said this is not a server,
and the password was `swordfish`, the above will be filled out like
this:

     <!--
     #  Macro: server_flag choice
     #  Q: Is this a server?
     #  C: Yes:TRUE
     #  C: No:FALSE
     -->

     <!--
     # IF: NOT SERVER_FLAG = TRUE
     #
     #
     #
     # Macro: SERVER_ID String
     # Q: What's the Server ID?
     #
     #
     #
     #
     # ENDIF:
     -->

     <!--
     # Macro: password string
     # Q: What is the user password?
     -->

     <password>swordfish</password>

# AUTHOR

David Weintraub
[mailto:david@weintraub.name](mailto:david@weintraub.name)

# COPYRIGHT

Copyright (c) 2013 by David Weintraub. All rights reserved. This
program is covered by the open source BMAB license.

The BMAB (Buy me a beer) license allows you to use all code for whatever
reason you want with these three caveats:

1. If you make any modifications in the code, please consider sending them
to me, so I can put them into my code.
2. Give me attribution and credit on this program.
3. If you're in town, buy me a beer. Or, a cup of coffee which is what I'd
prefer. Or, if you're feeling really spendthrify, you can buy me lunch.
I promise to eat with my mouth closed and to use a napkin instead of my
sleeves.
