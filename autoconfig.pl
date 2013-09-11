#! /usr/bin/env perl
# autoconfig.pl 

########################################################################
#
# Use the comand "perldoc autoconfig.pl" for a complete explanation
# about this program.
#
########################################################################

use 5.8.8;   # Redhat and Solaris still are 5.8.8 
use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use File::Copy;
use File::Find;
use Sys::Hostname;

use constant {
    COMMENT_LINE	=> qr@^(?:<\!--|#|//)\s*@,
    COMMENT_MARK	=> qr@^(<\!--|#|//)@,		       #For capturing what the comment mark is
    ONE_PARAM		=> qr/\s+(.*)/,
    TWO_PARAMS		=> qr/\s+(\S+)\s+(?:-\s+)?(\S+)/, #Dash is optional
    ONE_TWO_PARAMS	=> qr/\s+(\S+)(?:\s+)?(\S+)?(?:\s+)?(\S+)?/, 
    START_XML_COMMENT	=> qq(<!--),
    END_XML_COMMENT	=>  qq(-->),
    NULL_OK		=> qr@^NULL(:?_OK)$@i,
};

use constant {
    MACRO		=> "MACRO",
    RANGE		=> "RANGE",
    FORMAT		=> "FORMAT",
    FORCE		=> "FORCE",
    FROM		=> "FROM",
    TO			=> "TO",
    QUESTION		=> "Q",
    HELP		=> "H",
    DEFAULT		=> "D",
    CHOICE		=> "C",
    IF			=> "IF",
    ENDIF		=> "ENDIF",
};

use constant {
    MACRO_LINE		=> qr/@{[COMMENT_LINE]}@{[MACRO]}:@{[ONE_TWO_PARAMS]}/i,	#Macro Name and Type
    RANGE_LINE		=> qr/@{[COMMENT_LINE]}@{[RANGE]}:@{[TWO_PARAMS]}/i, 
    FORMAT_LINE		=> qr/@{[COMMENT_LINE]}@{[FORMAT]}:@{[ONE_PARAM]}/i,
    FORCE_LINE		=> qr/@{[COMMENT_LINE]}@{[FORCE]}:@{[ONE_PARAM]}/i,
    FROM_LINE		=> qr/@{[COMMENT_LINE]}@{[FROM]}:@{[ONE_PARAM]}/i,
    TO_LINE		=> qr/@{[COMMENT_LINE]}@{[TO]}:@{[ONE_PARAM]}/i,
    QUESTION_LINE	=> qr/@{[COMMENT_LINE]}@{[QUESTION]}:@{[ONE_PARAM]}/i,
    HELP_LINE		=> qr/@{[COMMENT_LINE]}@{[HELP]}:@{[ONE_PARAM]}/i,
    CHOICE_LINE		=> qr/@{[COMMENT_LINE]}@{[CHOICE]}:@{[ONE_PARAM]}/i,
    DEFAULT_LINE	=> qr/@{[COMMENT_LINE]}@{[DEFAULT]}:@{[ONE_PARAM]}/i,
    IF_LINE		=> qr/@{[COMMENT_LINE]}@{[IF]}:\s+(?:(NOT)\s+)?(\S+)\s+(?:=\s)?(.*?)(?:\s*@{[END_XML_COMMENT]})/i,
    ENDIF_LINE		=> qr/@{[COMMENT_LINE]}@{[ENDIF]}:/i,
    ANSWER_LINE		=> qr/^(\S+)\s*=\s*(.*)/,	# macro_name = answer
};

my $answer_file		= "autoconfig.answers";
my $suffix		= ".template";
my $help_string		= "HELP!";
my $prev_string		= "PREV!";
my @directory_list	= qw(.);

########################################################################
# GET OPTIONS
#
my ( $test_option, $use_defaults, $help, $option_help );

GetOptions (
    "answers=s"		=> \$answer_file,
    "suffix=s"		=> \$suffix,
    "defaults"		=> \$use_defaults,
    "directory=s"	=> \@directory_list,
    "helpstring=s"	=> \$help_string,
    "prevstring=s"	=> \$prev_string,
    "test=s"		=> \$test_option,
    "help"		=> \$help,
    "options"		=> \$option_help,
) or pod2usage ( -message => "Error: Bad options" );

if ( defined $test_option
	and ( $test_option ne 'all' and $test_option ne 'templates' ) ) {
    pod2usage (
	-message =>  '-test must either be "all" or "templates"',
	-exitval => 2
    );
}

if ( $help ) {
    pod2usage ( -exitval => 0 )
}

if ( $option_help ) {
    pod2usage ( -verbose => 1 );
}
#
########################################################################

########################################################################
# MAIN PROGRAM
#

$suffix = ".$suffix" unless $suffix =~ /^\./; # Suffix must be prefixed by "."

#
# Find Template Files
#
my $file_list_ref = find_template_files($suffix, @directory_list);

#
# GET THE QUESTIONS FROM THOSE FILES
#
my ($macro_list_ref, $error_count) = parse_questions( $file_list_ref );

if ( $error_count ) {
    die qq(\n\nError: There are $error_count errors detected in the configuration templates.\n) .
    qq(Fix these errors before continuing.\n);
}

exit 0 if ( defined $test_option and $test_option eq "templates" ); #Just checking the templates. All okay

#
# FIND THE ALREADY FILLED IN ANSWERS
#

( $macro_list_ref, $error_count) = read_in_answers( $macro_list_ref, $answer_file );
if ( $error_count ) {
    die qq(\n\nError: There are $error_count errors detected in the answer file.\n) .
    qq(Fix these errors before continuing.\n);
}

#
# IF DEFAULT AUTO-FILL-IN IS SELECTED, ADD DEFAULTS TO THE ANSWERS
#

$error_count = fill_in_defaults( $macro_list_ref ) if $use_defaults;
if ( $error_count ) {
    die qq(\n\nError: There are $error_count errors detected in the default answers.\n) .
    qq(Fix these errors before continuing.\n);
}

#
# ASK THE QUESTIONS
#
($macro_list_ref) = ask_questions ( $macro_list_ref, $help_string, $prev_string );

exit 0 if ( $test_option ); #Don't create answer file or fill in template if just a test
#
# GENERATE ANSWER FILE
#

create_answer_file ( $macro_list_ref, $answer_file );

#
# FILL IN THE PARAMETERS IN THE TEMPLATE FILES
#

fill_in_templates( $macro_list_ref, $file_list_ref, $suffix );

#
########################################################################

########################################################################
# SUBROUTINES
########################################################################

########################################################################
# FIND_TEMPLATE_FILES
#
# Searches the directories for files with a suffix that the template
# files use.
#
# Param
#   * Suffix for the template files
#   * A list of directory trees to search (NOT A REFERENCE!)
#
# Returns
#   * A reference to a list of files with the suffix
#
sub find_template_files {
    my $suffix         = shift;
    my @directory_list = @_;

    my @file_list;
    find ( sub {
	    return unless /\Q${suffix}\E$/;
	    return unless -f;
	    push @file_list, $File::Find::name;
	}, @directory_list
    );
    wantarray ? return @file_list : return \@file_list;
}
#
########################################################################

########################################################################
# PARSE QUESTIONS
#
# Parses the questions and macros found in the various template files.
#
# Params:
#   * A reference to a list of the template files
# Returns:
#   * a reference to a list of the macros defined in the template files
#   * an error count of the problems found in the macros during definition
#
sub parse_questions {
    my @file_list = @{ shift() };

    my @macro_list;
    my %macro_hash;   #Used for detecting duplicate questions
    my $error_count = 0; #Number of "errors" in quesitons

    for my $file ( @file_list ) {
	open my $template_fh, "<:crlf", $file or
	die qq(Can't open template file "$file" for reading);

	my $file_line = 0;
	my $macro;
	while ( my $line = <$template_fh> ) {
	    chomp $line;
	    $file_line++;
	    if ( $line =~ MACRO_LINE ) {
		my $macro_name = $1;
		my $type = $2;
		my $null_ok = $3;
		$type = "string" unless defined $type;
		$null_ok = "" unless defined $null_ok;

		#
		# Close out previous Macro definition
		#
		if ( defined $macro ) {
		    push @macro_list, $macro;
		    $macro_hash{$macro_name} = $#macro_list;
		    $macro = undef;
		}

		#
		# Make sure not duplicate Macro name
		#
		if ( exists $macro_hash{$macro_name} ) {
		    my $macro = $macro_list[ $macro_hash{ $macro_name } ];
		    my $prev_file = $macro->File;
		    my $prev_line = $macro->Line;
		    warn qq(Macro "$macro_name" already exists: Found in file "$file" line: $file_line\n) .
		    qq(Previously found in file "$prev_file" in line $prev_line.);
		    $error_count++;
		}
		$macro = Question->new(
		    macro => $macro_name,
		    type => $type,
		    file => $file,
		    line => $file_line,
		);
		if ( not $macro ) {
		    die qq(Invalid Macro Type: "$type" for "$macro_name": File: $file line: $file_line\n);
		}
		if ( $macro->can("Null_ok") and $null_ok =~ NULL_OK ) {
		    $macro->Null_ok(1);
		}
	    }
	    elsif ( $line =~ RANGE_LINE ) {
		my $from = $1;
		my $to = $2;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->From($from) ) {
		    error ( $macro, "From", $from, $file, $file_line );
		    $error_count++;
		}
		if ( not defined $macro->To($to) ) {
		    error ( $macro, "To", $to, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ FORMAT_LINE ) {
		my $format = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line);
		    $error_count++;
		    next;
		}
		if ( not $macro->can("Format") ) {
		    error ( $macro, "Format", $format, $file, $file_line );
		    $error_count++;
		}
		elsif ( not defined $macro->Format($format) ) {
		    error ( $macro, "Format", $format, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ FORCE_LINE ) {
		my $format = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line);
		    $error_count++;
		    next;
		}
		if ( not $macro->can("Force") ) {
		    error ( $macro, "Force", $format, $file, $file_line );
		    $error_count++;
		}
		elsif ( not defined $macro->Force($format) ) {
		    error ( $macro, "Force", $format, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ FROM_LINE ) {
		my $from = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->From($from) ) {
		    error ( $macro, "From", $from, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ TO_LINE ) {
		my $to = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if  ( not defined $macro->To($to) ) {
		    error ( $macro, "To", $to, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ QUESTION_LINE ) {
		my $question = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->Question($question) ) {
		    error ( $macro, "Question", $question, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ HELP_LINE ) {
		my $help = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->Help($help) ) {
		    error ( $macro, "Help", $help, $file, $file_line );
		    $error_count++;
		}
	    }
	    elsif ( $line =~ DEFAULT_LINE ) {
		my $default = $1;
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->Default($default) ) {
		    error ( $macro, "Default", $default, $file, $file_line );
		}
	    }
	    elsif ( $line =~ CHOICE_LINE ) {
		my $choice = $1;
		my ($description, $value) = split ( /:/, $choice, 2 );
		if ( not defined $value ) {
		    error ( $macro, "Choice", $choice, $file, $file_line );
		    $error_count++;
		}
		my $selection = Question::Choice::Selection->new($description, $value);
		if ( not defined $macro ) {
		    warn qq(WARNING: Bad macro definition at "$file" on line $file_line\n);
		    $error_count++;
		    next;
		}
		if ( not defined $macro->Add_Choice($selection) ) {
		    warn qq(Cannot create Choice from "$choice". File "$file" Line $file_line\n);
		    $error_count++;
		}
	    }
	    elsif ( $line =~ IF_LINE ) {
		my $negation = $1;
		my $parameter = uc $2;
		my $value = $3;
		my $if_clause;
		if ( $negation ) {
		    $if_clause = If->new( $parameter, $value, 1 );
		} else {
		    $if_clause = If->new( $parameter, $value, 0 );
		}
		push @macro_list, $if_clause;
	    }
	    elsif ( $line =~ ENDIF_LINE ) {
		my $end_if = If::Endif->new;
		push @macro_list, $end_if;
	    }
	    elsif ( $line =~ COMMENT_LINE ) {
		next;	#Ignore comment lines that aren't special
	    }
	    else {  #End of comment lines means end of question
		if ( defined $macro ) {
		    push @macro_list, $macro;
		    $macro_hash{$macro->Macro} = $#macro_list;
		    $macro = undef;
		}
	    }
	}   # while ( my $line = <$template_fh> )
	if ( defined $macro ) {
	    push @macro_list, $macro;
	    $macro_hash{$macro->Macro} = $#macro_list;
	    undef $macro;
	}
    }	# for my $file ( @file_list )

    #
    # One more task: Make sure that each subclass has all the required parameters.
    #    * All must include a question
    #    * Regex and Date must include a Format parameter

    for my $macro ( @macro_list ) {

	next unless $macro->isa( "Question" ); #Skip non-questions

	if ( not defined $macro->Question ) { # Make sure all Macros have a Question
	    error ( $macro, "", "", $macro->File, $macro->Line, "Missing required QUESTION field" );
	    $error_count++;
	}

	if ( $macro->can("Format") and not defined $macro->Format ) {
	    error ( $macro, "", "", $macro->File, $macro->Line, "Missing required FORMAT field" );
	    $error_count++;

	if ( $macro->isa("Question::Default") and not $macro->Default ) {
	    error ( $macro, "", "", $macro->File, $macro->Line, "Default Macro missing default answer" );
	    $error_count++;
	}
	}
    } # for my $macro ( @macro_list )

    return ( \@macro_list, $error_count);
}
#
########################################################################

########################################################################
# BUILD_INDEX_HASH
#
# Builds a map of Macros to their location in the list of macros
#
# Params:
#   * A reference to a list of class Question objects
#   * Optional parameter. If not zero or undef, only index questions
#     without answers
# Returns:
#   * A reference to a hash mapping the macro name to its position in
#     the list
sub build_index_hash {
    my @macro_list =          @{ shift() };
    my $no_answered_questions =  shift;

    my %macro_index_hash;
    for my $macro_number (0..$#macro_list) {
	my $macro = $macro_list[$macro_number];

	next unless $macro->isa( "Question" );
	next if defined $macro->Answer and $no_answered_questions;

	my $macro_name = $macro->Macro;
	$macro_index_hash{ $macro_name } = $macro_number;
    }
    return wantarray ? %macro_index_hash : \%macro_index_hash;
}
#
########################################################################

########################################################################
# READ_IN_ANSWERS
#
# Read the answer file (if one exists) and adds these answers to the
# already defined macros.
#
# Params:
#   * A reference to a list of class Question objects
#   * A Text-based Answer file in Java Properties File format
#
# Returns:
#   * A new reference to the list of class Question objects
#   * Number of errors found in adding in answers
#
sub read_in_answers {
    my @macro_list = @{ shift() };
    my $answer_file = shift;

    #
    # Build a map of Question objects to their position in the list
    #
    my %macro_index = build_index_hash( \@macro_list );

    open my $answer_file_fh, "<:crlf", $answer_file or
	return \@macro_list;	#Cannot find Answer file. That's really okay

    my $file_line = 0;
    my $error_count = 0;
    while ( my $line = <$answer_file_fh> ) {
	chomp $line;
	$line =~ s/\r$//;	#Incase line has Windows CRLF line endings. Chomp doesn't remove \r.
	$file_line++;
	next if $line =~ COMMENT_LINE;	#Skip Comment Lines
	next if $line =~ /^\s*$/;	#Skip Empty Lines
	if ( $line =~ ANSWER_LINE ) {
	    my $macro_name = uc $1;
	    my $answer = $2;

	    if ( not exists $macro_index{ $macro_name } ) {
		warn qq(Macro "$macro_name" found in Answer file, but it isn't a define Macro\n);
		$error_count++;
		next;
	    }
	    my $position = $macro_index{ $macro_name };
	    my $macro = $macro_list[ $position ];
	    if ( $macro->can("Real_answer") ) { #Override the default verification
		if ( not defined $macro->Real_answer($answer) ) {
		    error ($macro_list[ $position ], "Answer", $answer, $answer_file, $file_line);
		    $error_count++;
		}
	    }
	    elsif ( not defined $macro->Answer($answer) ) {
		error ($macro_list[ $position ], "Answer", $answer, $answer_file, $file_line);
		$error_count++;
		next;
	    }
	}
    }
    return ( \@macro_list, $error_count );
}
#
########################################################################

########################################################################
# FILL_IN_DEFAULTS
#
# If a Macro has on answer, but has a default answer, this subroutine
# will the answer to the default answer
#
# Params
#   * A reference to a list of Question objects
# Returns
#   * The number of errors encountered
#
sub fill_in_defaults {
    my @macro_list = @{ shift() };

    my $number_of_errors = 0;
    for my $position (0..$#macro_list) {
	my $default = $macro_list[ $position ]->Default;
	my $answer =  $macro_list[ $position ]->Answer;
	if ( $default and not defined $answer ) {
	    if ( not defined $macro_list[ $position ]->Answer( $default ) ) {
		my $macro_name = $macro_list[ $position ]->Macro;
		my $file_name =  $macro_list[ $position ]->File;
		my $line_num =   $macro_list[ $position ]->Line;
		warn qq(Default answer "$default" is invalid for Macro "$macro_name"\n) .
		qq(Macro is define in file "$file_name" Line: $line_num);
		$number_of_errors++;
	    }
	}
    }
    return $number_of_errors;
}
#
########################################################################

########################################################################
# ASK_QUESTIONS
#
# This is the heart of the process. For any parameter that is found, and
# doesn't already have an answer, this process will create the answer
# for that macro. 
# 
# Several steps take place:
#
# * A new question only
#
sub ask_questions {
    my @macro_list  = @{ shift() };
    my $help_string = shift;

    # Need a reference to know if I should ask a question or not.
    my %question_hash = build_index_hash (\@macro_list);
    my %questions_to_ask_hash = build_index_hash(\@macro_list, 1);

    # If there are no questions to ask, just return
    return \@macro_list unless keys %questions_to_ask_hash;

    my $given_intro;
    my $question_number = 0;
    my @if_list;
    QUESTION_NUMBER:
    while ( $question_number <= $#macro_list ) {
	my $macro = $macro_list[$question_number];
	if ( $macro->isa("If") ) {
	    push @if_list, $macro;
	    $question_number++;
	    next;
	}
	if ($macro->isa("If::Endif") ) {
	    pop @if_list;
	    $question_number++;
	    next;
	}

	# See if this is one of the questions to ask
	my $macro_name = $macro->Macro;
	if ( not exists $questions_to_ask_hash{$macro_name} ) {
	    $question_number++;
	    next;
	}

	# See if If Clauses cause you not to need to answer equation
	for my $if (@if_list) {
	    my $if_parameter = $if->Parameter;
	    my $if_value = $if->Value;
	    my $if_question_number = $question_hash{$if_parameter};
	    my $if_macro = $macro_list[$if_question_number];
	    my $macro_value = $if_macro->Answer;

	    if ( defined $macro_value ) {
		if ( $if->Negation and $macro_value eq $if_value ) { # IF: NOT PARAM = VALUE
		    $question_number++; # Since NOT PARAM != VALUE, we skip this question
		    next QUESTION_NUMBER;
		} 
		if ( not $if->Negation and $macro_value ne $if_value ) { # IF: PARAM = VALUE
		    $question_number++; # Since PARAM != VALUE, we skip this question
		    next QUESTION_NUMBER;
		}
	    }
	} #for $if (@if_list)

	# Don't Ask on Default Types. These aren't really questions
	# Instead, this is a way to automatically set a default value
	# which can be edited in an answer file.
	#
	if ( $macro->isa("Question::Default") ) {
	    $macro->Answer($macro->Default);
	    $question_number++;
	    next QUESTION_NUMBER;
	}

	# Ask the Question
	if ( not $given_intro and not $test_option ) {
	    print qq(Need to ask you a few questions about this configuration.\n);
	    print qq(If you need help, type "$help_string" as the answer.\n);
	    print qq(You can quit out of this program at any time, and no configuration\n);
	    print qq(would have been built. You can then run this program at a later time.\n\n\n);
	    $given_intro = 1;
	}
    
	my $question = $macro->Question;
	my $help = $macro->Help;
	my $default = $macro->Default;
	my $from = $macro->From;
	my $to = $macro->To;
	my $format = $macro->Format if $macro->can("Format");
	my @choice_list = $macro->Choice_list if $macro->can("Choice_list");
	#
	# Needed for -test all: Are all questions answered?
	#
	my $file_name	= $macro->File;
	my $line_number = $macro->Line;

	if ( $test_option ) { #Don't ask questions: Show unanswered questions only
	    print qq(NO ANSWER: $macro_name in $file_name line #$line_number\n);
	    $question_number++;
	    next QUESTION_NUMBER;
	}

	for (;;) {
	    print "$question ";
	    if ( @choice_list ) {
		print "\n";
		my $counter = 1;
		foreach my $choice (@choice_list) {
		    print "    $counter). " . $choice->Description . "\n";
		    $counter++;
		}
		print "Answer: ";
	    }

	    print "($default) " if $default;
	    chomp (my $answer = <STDIN> );
	    if ( $answer =~ /^\s*$/ ) { #Didn't answer question
		if ( $default ) {
		    $macro->Answer( $default );
		    last;
		}
		elsif ( $macro->can("Null_ok" )
			and $macro->Null_ok ) {	#Answers can be null
		    $macro->Answer( $answer );
		}
		else {
		    print qq(You must answer the question.\n);
		    my $text = display_help_text( $macro );
		    print "$text\n\n";
		    next;
		}
	    }
	    if ( $answer eq $help_string ) {
		my $text = display_help_text( $macro );
		print "$text\n\n";
		next;
	    }
	    if ( not defined $macro->Answer($answer) ) {
		my $text = display_help_text( $macro );
		print "$text\n\n";
		next;
	    }
	    last;
	}
	$question_number++;
    } #while ( $question_number > $#macro_list )
    return \@macro_list;
}

########################################################################
# DISPLAY_HELP_TEXT
#
# Displays basic help text when help is requested
#
# PARAMS
#    Reference to Question Macro
#
# RETURNS
#   Help text to be displayed
#
sub display_help_text {
    my $macro = shift;

    my $from   = $macro->From;
    my $to     = $macro->To;
    my $format = $macro->Format if $macro->can("Format");
    my $help   = $macro->Help;
    my $type   = $macro->Type;

    my $text;
    if ( $from and $to ) {
	$text =  qq(Answer must be between $from and $to.\n);
    } elsif ( $from ) {
	$text =  qq(Answer must be greater than $from.\n);
    } elsif ( $to ) {
	$text =  qq(Answer must be less than $to.\n);
    }

    $text .= qq(Answer must be a type: $type\n);
    $text .= qq(Answer must be in this format: $format\n) if $format;
    $text .= qq($help\n) if $help;
    return $text;
} 

#
# GENERATE ANSWER FILE
#

########################################################################
# GENERATE ANSWER FILE
#
# Generates a file with all of the answers. Will also backup the old
# Answer file.
#
# PARAMS
#    * Reference to the list of Macros that contain all of the
#      question macros.
#    * Name of the Answer file. 
#
sub create_answer_file {
    my @macro_list = @{ shift() };
    my $answer_file = shift;

    if ( -e $answer_file ) {
	if (not move $answer_file, "$answer_file.backup") {
	    warn qq(Cannot backup answer file "$answer_file"\n);
	}
    }
    open my $answer_file_fh, ">", $answer_file or
	die qq(Can't open Answer file "$answer_file" for writing.);

    for my $macro (@macro_list) {
	my $file_text;
	if ( $macro->isa("Question") ) {
	    $file_text = question_answer( $macro );
	}
	elsif ( $macro->isa("If") ) {
	    $file_text = if_answer( $macro );
	}
	elsif ( $macro->isa("If::Endif" ) ) {
	    $file_text = endif_answer();
	}
	print $answer_file_fh "$file_text\n";
    }
    close $answer_file_fh;
}
#
########################################################################

########################################################################
# QUESTION_ANSWER
#
# Takes a macro and outputs a text that will look something like the
# original macro it came from, and the puts the answer below it. This
# is NOT an exact duplicate of the original macro definition. This
# is just used to help a user, looking at the Answer file, understand
# what the original question was about before setting the Answer.
#
# PARAMS
#    * Question Class object
# RETURNS
#    * Text to be used in Answer file
#
sub question_answer {
    my $macro = shift;

    my $macro_name = $macro->Macro;
    my $file_name  = $macro->File;
    my $file_line  = $macro->Line;
    my $type       = $macro->Type;
    my $answer     = $macro->Answer;
    my $question   = $macro->Question;
    my $help       = $macro->Help;
    my $from       = $macro->From;
    my $to         = $macro->To;
    my $default    = $macro->Default;

    # Parameters that only some Macros have...
    my @choice_list = $macro->Choice_list if $macro->can("Choice_list");
    my $format = $macro->Format if $macro->can("Format");

    my $answer_text;

    $answer_text .= "# @{[MACRO]}: $macro_name $type";
    if ( $macro->can("Null_ok") and $macro->Null_ok ) {
	$answer_text .= " NULL_OK";
    }
    $answer_text .= "\n";

    $answer_text .= "# @{[FORMAT]}: $format\n" if $format;
    $answer_text .= "# File: $file_name  Line $file_line\n";
    if ( not $macro->isa("Question::Choice") ) { #Don't put From and To range for Choice Macro
	$answer_text .= "# @{[FROM]}: $from\n" if $from;
	$answer_text .= "# @{[TO]}: $to\n" if $to;
    }
    $answer_text .= "# @{[DEFAULT]}: $default\n" if $default;

    if ( $question ) { #Should always be true
	for my $question_line (split /\n/, $question) {
	    $answer_text .= "# Q: $question_line\n";
	}
    }

    if ( $help ) { #Should always be true
	for my $help_line (split /\n/, $help) {
	    $answer_text .= "# H: $help_line\n";
	}
    }

    #
    # Choice List
    #
    for my $choice ( @choice_list ) {
	my $description = $choice->Description;
	my $value = $choice->Value;
	$answer_text .= "# C: $description:$value\n";
    }

    #
    # ANSWER
    #
    $answer_text .= "\n$macro_name = $answer\n" if defined $answer;

    return $answer_text;
}
#
########################################################################

########################################################################
# IF_ANSWER
#
# Text if an If Macro is given
#
# PARAMS
#    * If Class Object
# RETURNS
#    Text to use in Answer file
#
sub if_answer {
    my $macro = shift;

    my $parameter = $macro->Parameter;
    my $value = $macro->Value;

    if ( $macro->Negation ) {
	return "# IF: NOT $parameter = $value\n";
    }
    else {
	return "#IF: $parameter = $value\n";
    }
}
#
########################################################################

########################################################################
# ENDIF_ANSWER
#
# Returns the text if an Endif macro is hit
#
# PARAMS
#    N/A
# RETURNS
#   Text to use in Answer file
#
sub endif_answer {

    return "# ENDIF:\n";
}
#
########################################################################

########################################################################
# FILL_IN_TEMPLATES
#
# Reads through template files and fills in the required information
#
# PARAMS
#   * A reference to a list of Question, IF, and Endif objects
#   * A list of template files that need to be processed
#   * Template file suffix to be stripped from templates
# RETURN
#   ????
#
sub fill_in_templates {
    my @macro_list =     @{ shift() };
    my @template_list  = @{ shift() };
    my $suffix =         shift;

    #
    # All you need are answers. Make a hash Macro_name => answer
    #

    my %macro_hash;
    for my $macro ( @macro_list ) {
	if ( $macro->isa("Question") and defined $macro->Answer ) {
	    $macro_hash{ $macro->Macro } = $macro->Answer;
	}
    }

    #
    # Add in Environment variables into %macro_hash
    # Environment variables are in the form _ENV_VARNAME
    # For example _ENV_HOME = "/Users/David"
    #
    for my $environment_variable ( keys %ENV ) {
	my $macro_name = uc( "_ENV_" . $environment_variable );
	$macro_hash{$macro_name} = $ENV{$environment_variable};
    }

    #
    # Add in special Macro names. So far, these are _SP_HOSTNAME and _SP_SHORTHOSTNAME
    #

    my $hostname = hostname;
    ( my $short_hastname = $hostname ) =~ s/\..*//;	#Remove domain information
    $macro_hash{_SP_HOSTNAME} = $hostname;
    $macro_hash{_SP_SHORTHOSTNAME} = $short_hastname;

    my @if_list;	#List of If Macros

    for my $template_file ( @template_list ) {
	( my $config_file_name = $template_file ) =~ s/${suffix}$//;
	open my $template_fh, "<:crlf", $template_file or
	    die qq(Can't open Template file "$template_file" for reading\n);
	open my $config_fh, ">", $config_file_name or
	    die qq(Can't open Configuration File "$config_file_name" for writing\n);

	my $comment_symbol; #Capture comment symbol on "IF" lines
	my $file_line = 0;
FILE_LINE:
	for my $line ( <$template_fh> ) {
	    chomp $line;
	    $file_line++;

	    #
	    # Push @if_list on If Line and go to next line
	    #
	    if ( $line =~ IF_LINE ) {
		my $negation = $1;
		my $parameter = $2;
		my $value = $3;
		$line =~ COMMENT_MARK;
		$comment_symbol = $1;
		my $if;
		if ( $negation ) {
		    $if = If->new( $parameter, $value, 1 );
		} else {
		    $if = If->new( $parameter, $value, 0 );
		}
		push @if_list, $if;
		print $config_fh "$line\n";
		next FILE_LINE;
	    }

	    #
	    # Pop @if_list on Endif Lines and go to next line
	    #
	    if ( $line =~ ENDIF_LINE ) {
		pop @if_list;
		print $config_fh "$line\n";
		next FILE_LINE;
	    }

	    #
	    # Don't substitute line if If statements aren't true
	    #

	    for my $if ( @if_list ) {
		my $if_parameter = $if->Parameter;
		my $if_value =     $if->Value;
		my $if_negation =  $if->Negation;
		my $macro_value = "";
		$macro_value =  $macro_hash{ $if_parameter } if exists $macro_hash{ $if_parameter };

		if ( $if_negation and $if_value eq $macro_value ) {
		    if ( $line eq START_XML_COMMENT or $line eq END_XML_COMMENT) {
			$line = ""; # Remove start and end XML comments during if blotting
		    }
		    if ( not $comment_symbol eq START_XML_COMMENT ) {
			print $config_fh "$comment_symbol $line\n";
		    }
		    else {
			print $config_fh "@{[START_XML_COMMENT]} $line @{[END_XML_COMMENT]}\n";
		    }

		    next FILE_LINE;
		}
		if ( not $if_negation and $if_value ne $macro_value ) {
		    if ( $line eq START_XML_COMMENT or $line eq END_XML_COMMENT) {
			$line = ""; # Remove start and end XML comments during if blotting
		    }
		    if ( not $comment_symbol eq START_XML_COMMENT ) {
			print $config_fh "$comment_symbol $line\n";
		    }
		    else {
			print $config_fh "@{[START_XML_COMMENT]} $line @{[END_XML_COMMENT]}\n";
		    }
		    next FILE_LINE;
		}
	    }

	    #
	    # Line is okay to do substitution
	    #
	    my @macro_list = ( $line =~ /%(\w+)%/g );
	    for my $macro ( @macro_list ) {
		if ( exists $macro_hash{ uc $macro } ) {
		    my $macro_value = $macro_hash{ uc $macro };
		    $line =~ s/%$macro%/$macro_value/ig;
		}
		else {
		    warn qq(WARNING: Possible missing definition for macro "%$macro%": ) .
			qq(File "$template_file" Line: $file_line\n);
		}
	    } #for my $macro ( @macro_list )
	    print $config_fh "$line\n";
	} # for my $line ( <$template_fh> )
	close $config_fh;
    } # for my $template_file ( @template_list )
}
#
########################################################################

########################################################################
# PRINT ERROR
#
sub error {
    use Carp;

    my $macro = shift;
    my $method = shift;
    my $value = shift;
    my $file = shift;
    my $line = shift;
    my $reason = shift;

    if ( not defined $reason ) {
	warn qq(\nError in setting "$method" for Macro ") . $macro->Macro
	. qq(" with value "$value" in File "$file" on Line $line\n);
    }
    else {
	warn qq(\nError in Macro ") . $macro->Macro . qq(": $reason. File $file Line $line\n);
    }
    return;
}
#
########################################################################

########################################################################
# CLASS Question
#
# Stores a Question Type including possible answers.
#
# Actual questions are really sub-classes to the Question class. The
# Question Class provides the following methods and the constructor
# for all of the other classes.
#
# PUBLIC METHODS
#
# Macro:        Macro Name being set by question
# Question:     The Question
# Help:         The Help for the question
# Default:      The Default Answer (Uses "Validate" and "InRange" Method from sub-class)
# Answer:       The Answer (Verfies Answer using sub-classes Validate and InRange)
# From:         The lower bound of an answer (Uses Sub-class' Less_Than method)
# To:           The upper bound of an answer (Uses sub-class' Greater_Than method)
# Validate:     A Default Validate Method (Basically, everything is valid)
# File:		The name of the file where this Macro was defined (Used for error messages)
# Line:		The line number in that file (Used for error messages)
#
# METHODS PROVIDED BY SUB-CLASSES
#
# All Subclasses must provide the following methods
#
# Validate:     Validates the provided value is a valid sub-class item. Can use the
#               default Validate from the base Question class.
# InRange:      Is the Answer "In Range" between the "From" and "To". 
#               can provide it's own InRange method, or 
#
# Instead of providing an InRange method, a sub-class could provide the following
# methods. These are used by the Base Question class' InRange method.
#
# Greater_Than: A method to see if the first item is greater than
#               the second item. Return "1" on true and an undef on false.
# Less_Than:    A method to see if the first item is less than the
#               second item. Returns a "1" on true and an undef on false.
#
# SUB-CLASSES
#
# The following are the valid sub-classes for Questions. These represent the
# question types:
#
# String:       String Answer
# Word:         Case insensitive String Answer
# Number:       Numeric Answer
# Integer:      Integer Answer
# Choice:       Select from a list of choices
# Date:         Date Answer
# IPAddr:       An IP Address
# File:         A Valid File Name. File must exist
# Regex:        A Regular Expression
#
#
# SPECIAL SUB-CLASS METHODS
#
# The following methods are unique to these Subclasses
#
# Sub-Class: Words
#     Force:    Whether to force case the answer. Valid values
#               are "uc", "lc", or "ucfirst".

# Sub-Class: Date
#     Format:   Format of the date
#
# Sub-Class: Regex
#     Format:   Format of the Regular Expression
#
# Sub-Class: Choice
#     List:     List of Question::Choice::Selection Objects
#
# Sub-Class: Question::Choice::Selection
#
# Unlike the other sub-classes, Choices offer a selection of
# values to use. Thus must be treated a bit differently than
# normal. 
#
# This sub-class creates the Choice selections. Each Selection
# consists of the item to display as a selection and the
# value that will be used for the "actual answer". For example,
# a selection might say "New York Area Server", but the value may
# be the IP address for that New York Area Server".
#
# new:          Constructor for a Question::Choice::Selection
# Choice:       What to display for a choice.
# Value:        The actual value behind the choice.
#
package Question;
use Carp;

sub new {
    my $class = shift;
    my %params = @_;

    #
    # Standardize the Parameters
    # Remove the dash, double-dash in front of the parameter and
    # lowercase the name. Thus, -Question, --question, and question
    # are all the same parameter.
    #

    my %option_hash;

    my $question_type;
    for my $key (keys %params) {

	my $value = $params{$key};

	$key =~ s/^-*//;    #Remove leading dashes
	$key = ucfirst ( lc $key ); #Make Key look like Method Name

	if ( $key eq "Type" ) {
	    $question_type = ucfirst (lc $value);
	}
	else {
	    $option_hash{$key} = $value;
	}
    }


    if ( not defined $question_type ) {
	carp qq(Parameter "type" required for creating a new question.);
	return;
    } 

    if ( not exists $option_hash{Macro} ) {
	carp qq(Parameter "macro" required for creating a new question.);
	return;
    }

    #
    # The real "class" of this question includes the question type
    #

    my $self = {};
    $class .= "::$question_type";
    bless $self, $class;

    #
    # Verify that this is a valid question type
    #
    if ( not $self->isa( "Question" )) {
	carp qq(Invalid question type of $question_type);
	return;
    }

    $self->_type($question_type);

    #
    # Everything looks good! Let's fill up our question object
    #

    if ( defined $option_hash{Macro} ) {
	$self->_macro( $option_hash{Macro} );
    }
    else {
	carp qq(Parameter "macro" required for creating a new question);
	return;
    }

    for my $method ( keys %option_hash ) {
	my $method_set;
	if ( $self->can( $method ) ) {
	    $self->$method( $option_hash{ $method } );
	}
	else {
	    carp qq(Can't set "$method" for question type "$question_type");
	    return;
	}
    }

    return $self;
}

#
# Getter Method for Type (Can't modify Type)
#
sub Type {
    my $self = shift;
    return $self->_type;
}

# PRIVATE: Accessor Method for Macro type.
# Accessor method is private. We do't want
# anyone outside of this package to change
# the macro's type.

sub _type {
    my $self = shift;
    my $type = shift;

    if ( defined $type ) {
	$self->{TYPE} = uc $type;
    }

    return $self->{TYPE};
}

#
# Getter Method for Macro name
#
sub Macro {
    my $self = shift;

    return $self->_macro;
}

# PRIVATE: Accessor Method for Macro name.
# Accessor method is private. We don't want
# anyone outside of this package to change
# the macro's name!
#
sub _macro {
    my $self = shift;
    my $macro = shift;

    if ( defined $macro ) {
	$self->{MACRO} = uc $macro;
    }
    return $self->{MACRO};
}

#
# Accessor Method for "Question" text.
#
sub Question {
    my $self = shift;
    my $question = shift;

    if ( defined $question ) {
	if ( $self->{QUESTION} ) {
	    $self->{QUESTION} .= "\n$question";
	} else {
	    $self->{QUESTION} = $question;
	}
    }
    return $self->{QUESTION};
}

# Accessor Method for "Help" text.
#
sub Help {
    my $self = shift;
    my $help = shift;

    if ( defined $help ) {
	if ( $self->{HELP} ) {
	    $self->{HELP} .= "\n$help";
	} else {
	    $self->{HELP} = $help;
	}
    }
    return $self->{HELP};
}

sub Default {
    my $self = shift;
    my $default = shift;

    if ( defined $default ) {
	if ( not $self->Validate( $default ) ) {
	    return;
	}
	$self->{DEFAULT} = $default;
    }

    return $self->{DEFAULT};
}

sub Answer {
    my $self = shift;
    my $answer = shift;
    my $real_answer = shift; #For choice types only;

    if ( defined $answer ) {
	if ( not $self->Validate( $answer ) ) {
	    return;
	}
	if ( not $self->InRange( $answer ) ) {
	    return;
	}
	if ( $self->can( "Choice_list" ) and defined $real_answer ) {
	    $self->{ANSWER} = $real_answer;
	}
	else {
	    $self->{ANSWER} = $answer;
	}
    }

    return $self->{ANSWER};
}

sub To {
    my $self = shift;
    my $to   = shift;

    if ( defined $to ) {
	if ( not $self->Validate( $to ) ) {
	    return;
	}
	$self->{TO} = $to;
    }
    return $self->{TO};
}

sub From {
    my $self = shift;
    my $from = shift;

    if ( defined $from ) {
	if ( not $self->Validate( $from ) ) {
	    return;
	}
	$self->{FROM} = $from;
    }
    return $self->{FROM};
}

sub InRange {
    my $self = shift;
    my $answer = shift;

    if ( not defined $answer ) {
	carp qq(Answer not provided for "InRange" test);
	return;
    }
    if ( defined $self->From and not $self->Less_Than( $self->From, $answer ) ) {
	return; #Answer is greater than From
    }
    elsif ( defined $self->To and not $self->Greater_Than( $self->To, $answer ) ) {
	return; #Answer is greater than To
    }
    else {
	return 1;  #Answer is within the specified range
    }
}

#
# Default Validate Routine: All Answers are valid by default
#

sub Validate {
    my $self = shift;
    my $answer = shift;

    return 1;  #All strings are valid;
}

sub File {
    my $self = shift;
    my $file = shift;

    if ( defined $file ) {
	$self->{FILE} = $file;
    }

    return $self->{FILE};
}

sub Line {
    my $self = shift;
    my $line = shift;

    if ( defined $line ) {
	$self->{LINE} = $line;
    }
    return $self->{LINE};
}

package Question::String;
use base qw(Question);

sub Greater_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return $first ge $second;
}

sub Less_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return $first le $second;
}

sub Null_ok {
    my $self		= shift;
    my $null_ok		= shift;

    if ( defined $null_ok ) {
	if ( $null_ok  == 0 ) {
	    $self->{NULL_OK} = undef;
	}
	else {
	    $self->{NULL_OK} = 1;
	}
    }
    return $self->{NULL_OK};
}

########################################################################
# PACKAGE Question::Words
#
# This is a sub-class of Question::String. The sole difference is
# that Strings are case sensitive and words are not.
#
# Also, there's the ability to force Answers to be upper or lower case

package Question::Words;
use base qw(Question::String);

use Carp;

sub Force {
    my $self = shift;
    my $force = shift;

    if ( defined $force ) {
	$force = lc $force;
	if ( $force ne "uc" and $force ne "lc" and $force ne "ucfirst" ) {
	    carp qq(Force must be either "uc", "lc", or "ucfirst" );
	    return;
	}
	$self->{FORCE} = $force;
    }

    return $self->{FORCE};
}

sub Greater_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return uc $first gt uc $second;
}

sub Less_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return uc $first lt uc $second;
}

#
# Might need to force case the Answer
#
sub Answer {
    my $self = shift;
    my $answer = shift;

    if ( not defined $answer ) {
	return $self->SUPER::Answer;
    }

    if ( defined $self->Force and $self->Force eq "uc" ) {
	$answer = uc $answer;
    }

    if ( defined $self->Force and $self->Force eq "lc" ) {
	$answer = lc $answer;
    }
    if ( defined $self->Force and $self->Force eq "ucfirst" ) {
	$answer = ucfirst lc $answer;
    }

    return $self->SUPER::Answer( $answer );
}

package Question::Number;
use base qw(Question);

sub Validate {
    use Scalar::Util qw(looks_like_number);

    my $self = shift;
    my $value = shift;

    return looks_like_number $value;
}

sub Greater_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return $first >= $second;
}

sub Less_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    return $first <= $second;
}

package Question::Integer;
use base qw(Question::Number);

sub Validate {
    my $self = shift;
    my $value = shift;

    return $value =~ /^\d+$/;
}


package Question::Regex;
use base qw(Question);
use Carp;

#
# Pattern for Answer to Validate Against
#
sub Format {
    my $self = shift;
    my $pattern = shift;

    if ( defined $pattern ) {
	$self->{PATTERN} = $pattern;
    }
    return $self->{PATTERN};
}

sub From {
    my $self = shift;

    return;  #Regular Expressions have no range
}

sub To {
    my $self = shift;

    return; #Regular Expressions have no range
}

sub InRange {
    my $self = shift;
    my $answer = shift;

    return 1;  #Regular Expressions have no "Range"
}

sub Validate {
    my $self = shift;
    my $answer = shift;

    my $pattern = $self->Format;

    # Must have Pattern to Verify Regular Expression Against
    if ( not defined $self->Format ) {
	carp qq(No format set for regular expression to match);
	return;
    }

    # Use "eval" just incase $pattern is a bad regular expression
    return eval { $answer =~ /$pattern/; };
}

########################################################################
# CLASS Question::Date
#
# This uses a Format to determine the format of the date, this program
# has to figure out how to parse the date by parsing the format.
#
# The format uses the following symbols:
#
#   M: Month
#   D: Day
#   Y: Year
#   h: hour
#   m: minute
#   s: second
#   a: am/pm marker (lowercase)
#   A: am/pm marker (uppercase)
#
# Date will be stored as the number of seconds since January 1, 1970
# (standard Unix format) thus this is really a sub-class of
# Question::Integer
#
#
package Question::Date;
use base qw(Question::Integer);

use Carp;
use Time::Local;

use constant {
    SECONDS_LOCATION => 0,
    MINUTES_LOCATION => 1,
    HOURS_LOCATION =>	2,
    MDAY_LOCATION =>	3,
    MONTH_LOCATION =>	4,
    YEAR_LOCATION =>	5,
};

sub _time_hash {
    my $key = shift;
    my %hash = (
	s => SECONDS_LOCATION,
	m => MINUTES_LOCATION,
	h => HOURS_LOCATION,
	D => MDAY_LOCATION,
	M => MONTH_LOCATION,
	Y => YEAR_LOCATION,
	a => undef,
	A => undef,
    );
    if ( $key ) {
	return $hash{$key};
    }
    else {
	return keys %hash;
    }
}

sub _convert_to_seconds {
    my $self = shift;
    my $date = shift;

    if ( not $date ) {
	return;
    }
    # @time_list will be used by the timegm function
    # for converting time to seconds. 
    my @time_list = qw(0 0 0 1 1 1970);	#Default Values
    my $format = $self->Format;

    if ( not defined $format ) {
	carp qq(Missing FORMAT field for date. Cannot convert to number of seconds since EPIC\n);
	return;
    }

    my $meridian_offset = 0;  #Offset due to AM/PM regulator

    for my $masking_char ( _time_hash() ) {	#For each possible char in mask

	# Find if Masking character is in the Format (and how many of them)
	( my $mask = $format) =~ s/[^$masking_char]//g;
	if ( not $mask ) { #masking_char not in format string
	    next;
	}
	my $mask_length = length $mask; # Is it "YY" or "YYYY"?

	# Find where the mask is in the format, and then take a substring
	# at that location (and the length of the mask
	my $location = index($format, $mask);
	if ( $location == -1 ) { #Can't find mask char in format string
	    next;
	}
	my $value = substr( $date, $location, $mask_length);
	my $position = _time_hash( $masking_char ); #Position in the @time_list array
	if ( defined $position ) {
	    $time_list[$position] = $value;
	} else {  #AM/PM Indicator
	    if    ( $mask_length == 2 and $masking_char eq "A" and $value eq "AM" ) {
		$meridian_offset = 0;
	    }
	    elsif ( $mask_length == 2 and $masking_char eq "A" and $value eq "PM" ) {
		$meridian_offset = 12;
	    }
	    elsif ( $mask_length == 1 and $masking_char eq "A" and $value eq "A"  ) {
		$meridian_offset = 0;
	    }
	    elsif ( $mask_length == 1 and $masking_char eq "A" and $value eq "P"  ) {
		$meridian_offset = 12;
	    }
	    else {
		carp qq(Bad Meridian Marker);
		return;
	    }
	}
    }
    #
    # Hours and Month should be numeric
    #
    if ( $time_list[HOURS_LOCATION] !~ /^\d+$/ 
	    or $time_list[MONTH_LOCATION] !~ /^\d+$/ ) {
	return;
    }
    $time_list[HOURS_LOCATION] += $meridian_offset; #If PM, must add 12 to it
    $time_list[MONTH_LOCATION] -= 1; #Months in timegm go from 0-11. Not 1-12

    #
    # At this point, we have the time values, and verified the date against the
    # format for those time values. However, there may be other characters in 
    # the Format, and we need to verify those characters too.
    #
    # We will create a regular expression for those. For example, if the format
    # is YYYY.MM.DD, we don't want the user entering YYYY/MM/DD.
    #
    # First turn off the magic of the non-time characters in format, so
    # YYYY.MM.DD becomes /YYYY\.MM\.DD/, then replace the time chars with ".",
    # so format becomes /....\...\.../. Now we can compare the date vs. that
    # regular expression "2012.06.18" =~ /....\...\.../, but
    # 2012-06-18 !~ /....\...\.../.
    #

    $format = $self->Format;  #Just in case it was changed earlier

    # Backslash all "special" regular expression characters
    $format =~ s/([\.\*\+\?\^\$])/\\$1/g;

    for my $masking_char ( _time_hash() ) { #Replace date mask chars with "."
	$format =~ s/${masking_char}/./g;
    }

    if ( $date !~ /$format/ ) {
	return; # Format is YYYY-MM-DD, but user entered YYYY/MM/DD
    }

    my $time_in_seconds;
    eval { $time_in_seconds = timegm @time_list; };
    if ( $@ ) {
	return;  #Can't convert time into seconds
    }
    else {
	return $time_in_seconds;
    }
}

sub Format {
    my $self = shift;
    my $format = shift;

    if ( defined $format ) {
	$self->{FORMAT} = $format;
    }

    return $self->{FORMAT};
}

sub Validate {
    my $self = shift;
    my $value = shift;

    if ( not $value = $self->_convert_to_seconds( $value ) ) {
	return;
    }
    return $self->SUPER::Validate( $value );
}

sub Greater_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    $first = $self->_convert_to_seconds ( $first );
    $second = $self->_convert_to_seconds ( $second );

    if ( not defined $first or not defined $second ) {
	return;
    }
    return $self->SUPER::Greater_Than( $first, $second );
}

sub Less_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    $first = $self->_convert_to_seconds ( $first );
    $second = $self->_convert_to_seconds ( $second );

    if ( not defined $first or not defined $second ) {
	return;
    }
    return $self->SUPER::Less_Than ( $first, $second );
}

package Question::Default;
use base qw(Question);
sub Validate {
    return 1;	#Always Valid
}
sub InRange {
    return 1;	#Always in range
}

package Question::Ipaddr;
use base qw(Question::Integer);
use Carp;

#
# Plain ol' subroutine. NOT A METHOD!
#
# An IP Address is a 8 digit hexidecimal number
# we'll use the following to convert an IP address
# to a hexidecimal number, and then use that
#

sub _convert_to_integer {
    my $ip_address = shift;

    if ( $ip_address !~ /\d+\.\d+\.\d+\.\d+/ ) {
	return;
    }

    my @octet_list = split /\./ => $ip_address;

    my $hex_value;
    for my $octet ( split /\./ => $ip_address ) {
	if ( $octet > 255 ) {
	    return;  #Octet can't be bigger than 255
	}
	$hex_value .= sprintf qq(%02X), $octet;
    }
    return hex $hex_value;
}

sub Validate {
    my $self = shift;
    my $value = shift;

    if (not $value = _convert_to_integer( $value ) ) {
	return;
    }
    return $self->SUPER::Validate( $value );
}

sub Greater_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    $first = _convert_to_integer ( $first );
    $second = _convert_to_integer ( $second );

    if ( not defined $first or not defined $second ) {
	return;
    }
    return $self->SUPER::Greater_Than( $first, $second );
}

sub Less_Than {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    $first = _convert_to_integer ( $first );
    $second = _convert_to_integer ( $second );

    if ( not defined $first or not defined $second ) {
	return;
    }
    return $self->SUPER::Less_Than ( $first, $second );
}

package Question::File;
use base qw(Question);

package Question::Choice;
use base qw(Question::Integer);
use Carp;

# Private Method: This allows you to set the value of the Choice
# List and get the choice list
#
sub _choice_list {
    my $self = shift;
    my $choice_list_ref = shift;

    if ( not exists $self->{CHOICE_LIST} ) {
	$self->{CHOICE_LIST} = [];
    }

    if ( defined $choice_list_ref ) {
	if ( ref $choice_list_ref eq "ARRAY" ) {
	    $self->{CHOICE_LIST} = $choice_list_ref;
	}
	else {
	    croak qq(Must pass list reference to _choice_list method);
	}
    }

    return wantarray ? @{ $self->{CHOICE_LIST} } : $self->{CHOICE_LIST};
}

# Retrieves the Choice List. Does not allow you to modify the choice list.
#
sub Choice_list {
    my $self = shift;

    my @choice_list = $self->_choice_list;
    return wantarray ? @choice_list : \@choice_list;
}

sub Add_Choice {
    my $self = shift;
    my $choice = shift;
    my $value = shift;

    my @choice_list = $self->_choice_list;

    my $choice_ref;
    if ( ref $choice eq "Question::Choice::Selection" and not defined $value) {
	$choice_ref = $choice;
    }
    elsif ( not ref $choice and defined $value ) {
	$choice_ref =  Question::Choice::Selection->new($choice, $value);
    }
    else {
	croak qq(invalid call to method Add_Choice ) .
	qq (must pass Question::Choice::Selection item or Choice and Value);
    }
    push @choice_list, $choice_ref;
    $self->_choice_list( \@choice_list );
return $choice_ref;
}

sub InRange {
    my $self = shift;
    my $answer = shift;

    $answer = $answer - 1;  #Arrays go from 0 to end and not 1 to end
    my @choice_list = $self->Choice_list;

    if ( $answer >= 0 and $answer <= $#choice_list ) {
	return 1;
    }
    else {
	return;	#Invalid Answer
    }
}

sub Get_Description {
    my $self = shift;
    my $choice = shift;

    if ( not $self->Validate( $choice ) or $self->InRange( $choice ) ) {
	return;
    }

    my @choice_list = $self->Choice_list;
    my $selection = $choice_list[$choice];

    return $selection->Description;
}

sub Get_Value {
    my $self = shift;
    my $choice = shift;

    if ( not $self->Validate( $choice ) or not $self->InRange( $choice ) ) {
	return;
    }

    my @choice_list = $self->Choice_list;
    my $selection = $choice_list[$choice - 1];

    return $selection->Value;
}

sub Real_answer {
    my $self = shift;
    my $answer = shift;  #This is an actual value and not a choice number

    if ( defined $answer ) {
	my @choice_list = $self->Choice_list;
	my $choice_number = 0;
	for my $choice (@choice_list) {
	    $choice_number++;
	    if ( $answer eq $choice->Value )  {
		return $self->Answer( $choice_number );
	    }
	}
	return;  #Invalid Choice
    }
    return $self->Answer;
}

sub Answer {
    my $self = shift;
    my $answer = shift;

    if ( defined $answer ) {
	if ( not $self->Validate( $answer ) ) {
	    return;
	}
	if ( not $self->InRange( $answer ) ) {
	    return;
	}

	#
	# Answer is defined. Look up the value.
	#
	my $real_answer = $self->Get_Value($answer);
	$self->SUPER::Answer($answer, $real_answer);
    }

    return $self->SUPER::Answer;
}

sub From {
    my $self = shift;

    return 1;   #Always from 1
}

sub To {
    my $self = shift;

    my @choice_list = $self->Choice_list;
    return  $#choice_list + 1;
}

package Question::Choice::Selection;
use Carp;

sub new {
    my $class =       shift;
    my $description = shift;
    my $value =       shift;

    if ( not defined $value ) {
	croak qq(Must include Description and Value when creating new $class);
	return;
    }

    my $self = {};
    bless $self, $class;

    $self->Description($description);
    $self->Value($value);

    return $self;
}

sub Description {
    my $self = shift;
    my $description = shift;

    if ( defined $description ) {
	$self->{DESCRIPTION} = $description;
    }

    return $self->{DESCRIPTION};
}

sub Value {
    my $self = shift;
    my $value = shift;

    if ( defined $value ) {
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

package Question::List;

sub new {
    my $class = shift;
    my $current_question = shift;
    my $previous_question = shift;

    my $self = {};
    bless $self, $class;

    $self->Current($current_question);
    $self->Previous($previous_question);

    return $self;
}

sub Current {
    my $self = shift;
    my $current_question = shift;

    if ( defined $current_question ) {
	$self->{CURRENT} = $current_question;
    }
    return $self->{CURRENT};
}

sub Previous {
    my $self = shift;
    my $previous_question = shift;

    if ( defined $previous_question ) {
	$self->{PREVIOUS} = $previous_question;
    }

    return $self->{PREVIOUS};
}

package If;
use Carp;

sub new {
    my $class = shift;
    my $param = shift;
    my $value = shift;
    my $negation = shift;

    my $self = {};
    bless $self, $class;

    $self->Parameter($param) if defined $param;
    $self->Value($value) if defined $value;
    $self->Negation($negation) if defined $negation;

    return $self;
}

sub Parameter {
    my $self = shift;
    my $param = shift;

    if ( defined $param ) {
	$self->{PARAMETER} = uc $param;
    }
    return $self->{PARAMETER};
}

sub Value {
    my $self = shift;
    my $value = shift;

    if ( defined $value ) {
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

sub Negation {
    my $self = shift;
    my $negation = shift;

    if ( defined $negation ) {
	$self->{NEGATION} = $negation;
    }

    return $self->{NEGATION};
}

package If::Endif;
use Carp;

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;
    return $self;
}

########################################################################
=pod

=head1 NAME

autoconfig.pl

=head1 SYNOPSIS

     autoconfig.pl [ -answers <answer_file> ] [ -suffix <template_suffix> ] \
	[ -test (all|templates) ] [ -defaults ] \
	[ -directory dir1 -directory dir2... ] [ helpstring <help_string> ]

or
    autoconfig.pl -help
or
    autoconfig.pl --options

=head1 DESCRPTION

This program looks for i<Template Files>, and turns those template files
into the required configuration files. It does this by looking for I<questions>
in these template files, finding the answers to these questions, and filling
in the macros with the correct answer. It then will generate an I<answer file>,
so the next time the configuration needs to be reexecuted, it won't have to reask
the questions.


=head1 OPTIONS

=over 10

=item -answers

The name of the answer file in I<Answer File Format>. The answer file is really nothing more
than a bunch of optional comment lines that start with "#" and a line with the I<macro name> and the
value of that macro. For example:

     # This is a comment
     # Here's another comment
     MY_MACRO = The macro's value

In the above, the macro I<MY_MACRO> is being set to the string I<The
macro's value>. This makes it easy to create a fresh answer file, or to
edit an existing one. When this program is executed, the answer file
will be rewritten with any newly answered macros, and the comments will
be changed to reflect the name of the template file that contained the
macro, and the line number of that started the definition, and other
information. This makes it easy to see what the I<question> was and
which template file it was located in. For example, the above might get
rewritten as:

    # MACRO: MY_MACRO STRING
    # File: ./foo/bar/some.template:23
    # Q: What is the value of your Macro?
    
    MY_MACRO = The macro's value

The default Answer file is called C<autoconfig.answers>

=item -test

A test run of the program. This can be used to test whether the
templates are valid and if all answers from the answer files were given,
and there are no unknown answers. Valid arguments are C<all> for both
the templates and answers, or C<templates> for just the templates.

=item -suffix

The suffix for the various template files. The default will be
I<.template>. When a template file is processed, the name of the
configuration file is the template name minus the suffix. For example,
F<config.properties.template> will become F<config.properties> in the
same folder where F<config.properties.template> was located.

=item -defaults 

If a I<Question> has a default answer, assume that the answer is the
default value, and don't ask the question. Default is to ask the
question for macros with no answer whether or not there is a default
answer.  =item -directory

=item -directory

This is the directory tree to search for template files. All files in
this directory tree with the given template suffix will be parsed and
turned into regular configuration files. This parameter my be repeated
as many times as needed.

The default is the current directory and will search all subdirectories
under the current directory.

=item -helpstring

This is what the user can type to get further help on a question. The
default is I<HELP!>.

=item -help

Displays the synopsis section of this document

=item -options

Displays the synopsis section and the option section to describe those
options.

=back 

=head1 TEMPLATE FILES

Template files look just like the configuration files they are for
except they contain the macro names in the place of the actual value of
the parameter. Imagine a regular Java properties file called
F<config.properties.> The template file would be called
F<config.properties.template> and would look like this:

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

You do this by defining a I<macro>. Macro definitions are made to look
like comments, so they don't affect the actual configuration files.
Macro lines can either start with a C<#> or double C<//>, so they can
look like a Properties file comment. If you are placing this inside an
XML file, you can define a macro by putting the E<lt>!-- on the\ line
before the macro definition and a --E<gt> after the line. That way, the
macro definition is enveloped in comments.

Macro definitions follow a simple format. For example, to define
C<%USER_NAME%> in the above, the macro definition would look something
like this:

    # MACRO: USER_NAME
    # Q: What is the name of the user?

And that's pretty much it. A macro definition needs a macro name and a
question which is simply a line that starts with a comment and a C<Q:>.
Macros can also contain a C<macro type>, so the above definition could
look like this too:

    # MACRO: USER_NAME STRING
    # Q: What is the name of the user?

The macro type (C<STRING> in this case) is the second parameter on the
C<# MACRO:> line. If a macro type isn't given, it is assumed to be a
macro type of string.

If you specify that the Macro type is either C<STRING> or C<WORDS>, you
can specify that the user could leave this as a blank value by
specifying C<NULL> or C<NULL_OK> after the type parameter.

    # MACRO PASSWORD STRING NULL_OK
    # Q: What is your password?

The following are all of the valid Macro types:

=over 10

=item STRING

The answer needs to be a string of some sort. Strings are case
sensitive.

=item WORDS

The answer needs to be words. Words are just like strings, but they're
not case sensitive. This comes in handy when you force the answer to be
in a particular range. You can also force the answer to be upper case,
lower case, or where the first word is capitalized.

=item NUMBER

The answer needs to be a valid number. A number is defined by the
I<looks_like_number> function from the Scalar::Util module.

=item INTEGER

The answer must be an integer.

=item DATE

The answer must be a date or time string. Dates must have a defined
I<Format>, so that the answer can be verified against that format.

=item REGEX

The answer must match the regular expression given by its I<Format>.

=item CHOICE

The answer must be one of the choices give.

=item IPADDR

The answer must be a valid IPv4 IP address.

=item DEFAULT

Default type macros don't ask questions, but simply provide a default as
given if there is not already an answer. This is a good way to provide a
particular value for a parameter, but allow sites to be able to modify
it in their answer files.

=back 

=head2 OTHER MACRO PARAMETERS

All macros have the following parameters. The only required parameters
are the Macro definition heading, and at least one I<Question> line.

=over 10

=item # MACRO:

This is the I<macro> definition line. The line takes one or two
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

=item # Q:

This line is the question to ask about the macro's value. There can be
multiple question lines.  Each question line will appear on its own
line, so you can format the question easier.

=item # H:

This is the help line. This allows you to provide further information
when a user requests help, or if the user gives an invalid answer. This
makes it easy to ask a brief question (What is the server name?), and
then provide more details in the help statement (the following are our
current servers...). Liek the question parameter, the help parameter can
also be multiple lines.

=item # D:

The default value. This is the answer to use if the user simply presses
E<lt>RETURNE<gt>. It is also the answer if the user uses the
C<-defaults> parameter when the program was executed.

=item # RANGE:

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
macro type, or if your I<to> value is less than the I<from> value.

If the macro type is I<Words>, the from values are case insensitive.

=item # FROM:

Defines the lowest possible answer permitted. If the macro type is
I<Words>, the from value is case insensitive.

The program will give you an error if your range does not match the
macro type, or if your I<to> value is less than the I<from> value.

=item # TO:

Defines the highest possible answer permitted.  If the macro type is
I<Words>, the from value is case insensitive.

The program will give you an error if your range does not match the
macro type, or if your I<to> value is less than the I<from> value.

=back

=head2 OTHER PARAMETERS

Some macros types take other possible parameters:

=over 10

=item DATE

Dates can take a possible I<Format> parameter. This parameter is the
format of the date that you expect. Dates can contain any number of date
or time parameters. The answer given must match the format, or the
answer will be rejected. Dates can contain the following special
charcters:

=over 4

=item Y

Year

=item M

Month

=item D

Day of the Month

=item h

Hour

=item m

Minute

=item s

Second

=item A

AM/PM Meridian marker. Must be uppercase

=item a

AM/PM Meridian marker. Must be lowercase

=back

All other characters in the date format must match exactly as written.
Here's an example of a I<Date> macro definition:

    # MACRO: START_DATE DATE
    # FORMAT: YYYY-MM-DD
    # Q: Default start date for reports

In this case, the date is expected to have a four character year, and a
2 character month and day separated by dashes. For example:

=over 10

=item  2001-01-15

Valid

=item 20010115

Invalid

=item 2001/01/15

Invalid

=back

You can also do time definitions too:

    # MACRO: EXECUTE_CLEANUP DATE
    # FORMAT: hh:mm
    # Q: At what time should the clean up routine run?

In this case, you are only expecting an hour and minute for the time.
Since the C<A> format character isn't specified, this will be a 24 hour
time. The following is a 12 hour time:

    # MACRO: EXECUTE_CLEANUP DATE
    # FORMAT: hh:mmA
    # Q: At what time should the clean up routine run?

In this case, the time would be something like C<11:45A>. If you double
up the C<A> character, the format would be something like this:

    # MACRO: EXECUTE_CLEANUP DATE
    # FORMAT: hh:mmAA
    # Q: At what time should the clean up routine run?

In this case, the time would be something like C<11:45AM>.

=item REGEX

Regular expressions also take a I<Format> parameter. However, this is
the regular expression that the answer must match. For example:

    # MACRO: PHONE_NUMBER REGEX
    # FORMAT: \d{3,3}-\d(3,3}-\d{4,4}
    # Q: What is the phone number (including the area code)?

=item WORDS

Macros of type I<Words> can take a I<Force> parameter. This parameter
tells you whether to force the answer to be uppercase, lowercase, or
capital case. The user does not need to put the macro in this case, the
answer will simply be forced into that case. For example:

    # Macro: USER_ID WORDS
    # FORCE: UC
    # Q: User Name?

In this case, the C<USER_ID> will always be upper case if the user
entered in C<David>, the answer will be C<DAVID>. The force macro can
take the following values:

=over 5

=item UC

Force answer to uppercase.

=item LC

Force answer to lowercase.

=item UCFIRST

Force answer to capitalize only the first character of the answer.

=back

=back

=head2 The CHOICE Macro

The Choice macro is a bit different from the other macros. This will
give the user a selection of choices they can choose. This macro does
not take a range (the range is the range of choices), or a I<From> or a
I<To> parameter. If a default is given, it is the number of the choice
to select.

Choice parameters start with a C<# C:> and contain a description to
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

If the user selects I<3>, the C<CACHE_SIZE> macro will be set to C<10>.
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

=head1 SPECIAL MACRO NAMES

There are two sets of special macro names. These are not set by macro
questions, but by the environmet.

=head2 _ENV_ Macros

The C<_ENV_> macros start with the string C<_ENV_> and the name of the
environment variable is appended to the end of the macro name. There is
one of these special C<_ENV_> macros for each environment variable in
your system. Case is insignificant, so if you have C<PATH> and C<path>
as two environment variables, only one will be C<_ENV_PATH>, but we
cannot say which one would be used.

This allows you to use environment variables in your Macros.

=head2 _SP_ Macros

There are some I<special> macro values that are automatically generated.
These include:

=over 4

=item * C<_SP_HOSTNAME>: The hostname of the system (may include domain
name).

=item * C<_SP_SHORTHOSTNAME_>: The hostname of the system minus any
domain name information (everything after the first C<.> is stripped
off).

=back

=head1 ETCETRICITIES

Included in this project is a sample template. Use this to explore this program.

=head2 XML HTML File Handling

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
and the password was C<swordfish>, the above will be filled out like
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

=head1 AUTHOR

David Weintraub
L<mailto:david@weintraub.name>

=head1 COPYRIGHT

Copyright (c) 2013 by David Weintraub. All rights reserved. This
program is covered by the open source BMAB license.

The BMAB (Buy me a beer) license allows you to use all code for whatever
reason you want with these three caveats:

=over 4

=item 1.

If you make any modifications in the code, please consider sending them
to me, so I can put them into my code.

=item 2.

Give me attribution and credit on this program.

=item 3.

If you're in town, buy me a beer. Or, a cup of coffee which is what I'd
prefer. Or, if you're feeling really spendthrify, you can buy me lunch.
I promise to eat with my mouth closed and to use a napkin instead of my
sleeves.

=back

=cut
