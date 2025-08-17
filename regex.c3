module regex;
import std::ascii;

const REGEX_DOT_MATCH_NEWLINE =true;
const MAX_REGEXP_OBJECTS  =64;    // Max number of regex symbols in expression.
const MAX_CHAR_CLASS_LENGTH  =64;

const END_LINE='\0';
const MAX_QUANTIFICATION_VALUE=1024;


enum RegexPatternType
{
    REGEX_END_OF_PATTERN,     // is a sentinel used to indicate end-of-pattern
    REGEX_DOT,
    REGEX_BEGIN,
    REGEX_DOLLAR_END,
    REGEX_QUESTION_MARK,
    REGEX_STAR,
    REGEX_LAZY_STAR,
    REGEX_PLUS,
    REGEX_LAZY_PLUS,
    REGEX_REGULAR_CHAR,
    REGEX_CHAR_CLASS,
    REGEX_INVERSE_CHAR_CLASS,
    REGEX_DIGIT,
    REGEX_NOT_DIGIT,
    REGEX_ALPHA,
    REGEX_NOT_ALPHA,
    REGEX_WHITESPACE,
    REGEX_NOT_WHITESPACE,
    REGEX_QUANTIFIER
}

struct RegexNode
{
    RegexPatternType patternType;
    union {
        char regexChar;
        char *classCharPtr;
        ushort[2] minMaxQuantifiers;  // {m,n} quantifier
    }
}

struct Regex
{
    RegexNode[MAX_REGEXP_OBJECTS] compiledRegexArray;
    char[MAX_CHAR_CLASS_LENGTH] classCharArray;
    bool isPatternValid;
    ZString errorMessage;
}

struct Matcher
{
    int foundAtIndex;
    int matchLength;
    bool isFound;
}

fn void compile(Regex* regex,char* pattern) @extern("regexCompile")
{
    if (regex == null) return;
    regex.isPatternValid = true;
    regex.errorMessage = "Success";
    RegexCompiler regexCompiler = {
            .classCharIndex = 0,
            .patternIndex = 0,
            .regexIndex = 0,
            .isQuantifiable = false,
            .regex = regex
    };

    if (pattern == null) {
        regex.isPatternValid = false;
        regex.errorMessage = "NULL pattern string";
        return;
    }

    while (pattern[regexCompiler.patternIndex] != END_LINE && ((regexCompiler.regexIndex + 1) < MAX_REGEXP_OBJECTS)) {
        char charInPattern = pattern[regexCompiler.patternIndex];

        switch (charInPattern) {
            case '^':   // Meta-characters
                setBeginMetaChar(&regexCompiler);
                break;
            case '$':
                setDollarEndMetaChar(&regexCompiler);
                break;
            case '.':
                setDotMetaChar(&regexCompiler);
                break;
            case '*':
                setStarMetaChar(&regexCompiler, pattern);
                break;
            case '+':
                setPlusMetaChar(&regexCompiler, pattern);
                break;
            case '?':
                setQuestionMarkMetaChar(&regexCompiler);
                break;
            case '\\':  // Escaped characters
                resolveEscapedCharacterClasses(&regexCompiler, pattern);
                break;
            case '[':   // Character class
                resolveCharacterClass(&regexCompiler, pattern);
                break;
            case '{':   // Quantifier
                resolveQuantification(&regexCompiler, pattern);
                break;
            default:    // Regular characters
                setRegularChar(&regexCompiler, charInPattern);
        }

        if (!regex.isPatternValid) {
            return;
        }
        regexCompiler.patternIndex++;
        regexCompiler.regexIndex++;
    }

    setRegexPatternType(REGEX_END_OF_PATTERN, &regexCompiler);

}

fn Matcher match(Regex* regex,char* text) @extern("regexMatch")
{

    Matcher matcher = {.foundAtIndex = 0, .matchLength = 0, .isFound = false};
    if (regex == null || !regex.isPatternValid) return matcher;

    if (regex.compiledRegexArray[0].patternType == REGEX_BEGIN) {
        matcher.isFound = matchPattern(&regex.compiledRegexArray + 1, &matcher, text);
        return matcher;
    }

    do {
        if (matchPattern(&regex.compiledRegexArray, &matcher, text)) {
            if (*text == END_LINE) {
                matcher.isFound = false;
                return matcher;
            }
            matcher.isFound = true;
            return matcher;
        }
        matcher.foundAtIndex++;
    } while (*text++ != END_LINE);

    return matcher;
}



struct RegexCompiler
{
    Regex* regex;
    ushort regexIndex;
    ushort patternIndex;
    ushort classCharIndex;
    bool isQuantifiable;
}

fn void setBeginMetaChar(RegexCompiler *regexCompiler) @extern("setBeginMetaChar")
{
    regexCompiler.isQuantifiable = false;
    setRegexPatternType(REGEX_BEGIN, regexCompiler);
}
fn void setDollarEndMetaChar(RegexCompiler *regexCompiler) @extern("setDollarEndMetaChar")
{
    regexCompiler.isQuantifiable = false;
    setRegexPatternType(REGEX_DOLLAR_END, regexCompiler);
}
fn void setDotMetaChar(RegexCompiler *regexCompiler) @extern("setDotMetaChar")
{
    regexCompiler.isQuantifiable = true;
    setRegexPatternType(REGEX_DOT, regexCompiler);
}
fn void setStarMetaChar(RegexCompiler *regexCompiler, char *pattern) @extern("setStarMetaChar")
{
    if (!regexCompiler.isQuantifiable) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Non-quantifiable before '*'";
        return;
    }
    regexCompiler.isQuantifiable = false;

    if (pattern[regexCompiler.patternIndex + 1] == '?') {
        setRegexPatternType(REGEX_LAZY_STAR, regexCompiler);
        regexCompiler.patternIndex++;
    } else {
        setRegexPatternType(REGEX_STAR, regexCompiler);
    }
}
fn void setPlusMetaChar(RegexCompiler *regexCompiler, char *pattern) @extern("setPlusMetaChar")
{
    if (!regexCompiler.isQuantifiable) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Non-quantifiable before '+'";
        return;
    }

    if (pattern[regexCompiler.patternIndex + 1] == '?') {
        setRegexPatternType(REGEX_LAZY_PLUS, regexCompiler);
        regexCompiler.patternIndex++;
    } else {
        setRegexPatternType(REGEX_PLUS, regexCompiler);
    }
}
fn void setQuestionMarkMetaChar(RegexCompiler *regexCompiler) @extern("setQuestionMarkMetaChar")
{
    if (!regexCompiler.isQuantifiable) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Non-quantifiable before '?'";
        return;
    }
    setRegexPatternType(REGEX_QUESTION_MARK, regexCompiler);
}
fn void setRegexPatternType(RegexPatternType patternType, RegexCompiler *regexCompiler) @extern("setRegexPatternType")
{
    regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].patternType=patternType;
}
fn void resolveEscapedCharacterClasses(RegexCompiler *regexCompiler, char *pattern) @extern("resolveEscapedCharacterClasses")
{
    if (pattern[regexCompiler.patternIndex + 1] != END_LINE) {
        regexCompiler.isQuantifiable = true;
        regexCompiler.patternIndex++;   // Skip the escape-char

        RegexPatternType patternType;
        switch (pattern[regexCompiler.patternIndex]) {
            case 's':
                patternType = REGEX_WHITESPACE;
                break;
            case 'S':
                patternType = REGEX_NOT_WHITESPACE;
                break;
            case 'w':
                patternType = REGEX_ALPHA;
                break;
            case 'W':
                patternType = REGEX_NOT_ALPHA;
                break;
            case 'd':
                patternType = REGEX_DIGIT;
                break;
            case 'D':
                patternType = REGEX_NOT_DIGIT;
                break;
            default:
                patternType = (RegexPatternType)0;
                break;
        }

        if (patternType > (RegexPatternType)0) {  // Check the next Meta-character:
            setRegexPatternType(patternType, regexCompiler);
        } else {
            setRegexPatternType(REGEX_REGULAR_CHAR, regexCompiler); // Escaped character, e.g. '.' or '$'
            regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].regexChar = pattern[regexCompiler.patternIndex];
        }
    }
}
fn void resolveCharacterClass(RegexCompiler *regexCompiler, char *pattern) @extern("resolveCharacterClass")
{
    ushort bufferBegin = regexCompiler.classCharIndex;    // Remember where the char-buffer starts.
    regexCompiler.patternIndex++;  // Skip '['
    regexCompiler.isQuantifiable = true;

    if (pattern[regexCompiler.patternIndex] == '^') {    // Look-ahead to determine if negated
        setRegexPatternType(REGEX_INVERSE_CHAR_CLASS, regexCompiler);
        regexCompiler.patternIndex++; // Increment index to avoid including '^' in the char-buffer
        if (pattern[regexCompiler.patternIndex] == END_LINE) {
            regexCompiler.regex.isPatternValid = false;
            regexCompiler.regex.errorMessage = "Incomplete pattern, missing non-zero char after '^'";
            return;
        }
    } else {
        setRegexPatternType(REGEX_CHAR_CLASS, regexCompiler);
    }

    while (pattern[regexCompiler.patternIndex] != END_LINE && pattern[regexCompiler.patternIndex] != ']') {
        char charInPattern = pattern[regexCompiler.patternIndex];

        if (charInPattern == '\\') {
            if (regexCompiler.classCharIndex >= MAX_CHAR_CLASS_LENGTH - 1 || pattern[regexCompiler.patternIndex + 1] == END_LINE) {
                regexCompiler.regex.isPatternValid = false;
                regexCompiler.regex.errorMessage = "Incomplete pattern, missing non-zero char after '\\'";
                return;
            }
            regexCompiler.regex.classCharArray[regexCompiler.classCharIndex] = pattern[regexCompiler.patternIndex];
            regexCompiler.classCharIndex++;
            regexCompiler.patternIndex++;

        } else if (regexCompiler.classCharIndex >= MAX_CHAR_CLASS_LENGTH) {
            regexCompiler.regex.isPatternValid = false;
            regexCompiler.regex.errorMessage = "Exceeded internal buffer";
            return;
        }
        regexCompiler.regex.classCharArray[regexCompiler.classCharIndex] = pattern[regexCompiler.patternIndex++];
        regexCompiler.classCharIndex++;
    }

    if (regexCompiler.classCharIndex >= MAX_CHAR_CLASS_LENGTH) { // Check for too long patterns. Such as [00000000000000000000000000000000000000][
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Too long char class pattern";
        return;
    }

    if (pattern[regexCompiler.patternIndex] != ']') {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Non terminated class ']'";
        return;
    }
    regexCompiler.regex.classCharArray[regexCompiler.classCharIndex] = END_LINE;// Null-terminate string end
    regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].classCharPtr = &regexCompiler.regex.classCharArray[bufferBegin];
    regexCompiler.classCharIndex++;
}
fn void resolveQuantification(RegexCompiler *regexCompiler, char *pattern) @extern("resolveQuantification")
{
    if (!regexCompiler.isQuantifiable) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Non-quantifiable before '{m,n}'";
        return;
    }
    regexCompiler.patternIndex++;  // Skip '{'

    if (pattern[regexCompiler.patternIndex] == END_LINE) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Dangling '{' quantifier";
        return;
    }

    int minQuantifierValue = 0;
    do
    {
        char quantifierValueChar = pattern[regexCompiler.patternIndex];
        if (!ascii::is_digit(quantifierValueChar)) {
            regexCompiler.regex.isPatternValid = false;
            regexCompiler.regex.errorMessage = "Non-digit min value in quantifier";
            return;
        }
        minQuantifierValue = 10 * minQuantifierValue + (int) (quantifierValueChar - '0');
        regexCompiler.patternIndex++;
    }
    while (pattern[regexCompiler.patternIndex] != ',' && pattern[regexCompiler.patternIndex] != '}');

    if (minQuantifierValue > MAX_QUANTIFICATION_VALUE) {
        regexCompiler.regex.isPatternValid = false;
        regexCompiler.regex.errorMessage = "Min value too big in quantifier";
        return;
    }
    regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].minMaxQuantifiers[0] = (ushort)minQuantifierValue;

    if (pattern[regexCompiler.patternIndex] == ',') {
        regexCompiler.patternIndex++;  // Skip ','
        if (pattern[regexCompiler.patternIndex] == END_LINE) {
            regexCompiler.regex.isPatternValid = false;
            regexCompiler.regex.errorMessage = "Dangling ',' quantifier";
            return;
        }

        if (pattern[regexCompiler.patternIndex] == '}') {
            regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].minMaxQuantifiers[1] = MAX_QUANTIFICATION_VALUE;
        } else {

            int maxQuantifierValue = 0;
            while (pattern[regexCompiler.patternIndex] != '}') {
                char quantifierValueChar = pattern[regexCompiler.patternIndex];
                if (quantifierValueChar == END_LINE || !ascii::is_digit(quantifierValueChar)) {
                    regexCompiler.regex.isPatternValid = false;
                    regexCompiler.regex.errorMessage = "Non-digit max value in quantifier";
                    return;
                }

                maxQuantifierValue = 10 * maxQuantifierValue + (int) (quantifierValueChar - '0');
                regexCompiler.patternIndex++;
            }

            if (maxQuantifierValue > MAX_QUANTIFICATION_VALUE || maxQuantifierValue < minQuantifierValue) {
                regexCompiler.regex.isPatternValid = false;
                regexCompiler.regex.errorMessage = "Max value too big or less than min value in quantifier";
                return;
            }
            regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].minMaxQuantifiers[1] =(ushort)maxQuantifierValue;
        }
    }

    setRegexPatternType(REGEX_QUANTIFIER, regexCompiler);
}
fn void setRegularChar(RegexCompiler *regexCompiler, char charInPattern) @extern("setRegularChar")
{
    regexCompiler.isQuantifiable = true;
    setRegexPatternType(REGEX_REGULAR_CHAR, regexCompiler);
    regexCompiler.regex.compiledRegexArray[regexCompiler.regexIndex].regexChar = charInPattern;
}

fn bool matchPattern(RegexNode *regex, Matcher *matcher, char *text) @extern("matchPattern")
{
    int previousMatch = matcher.matchLength;

    do {
        if (regex[0].patternType == REGEX_END_OF_PATTERN || regex[1].patternType == REGEX_QUESTION_MARK) {
            return matchQuestionMark(regex, (regex + 2), text, matcher);

        } else if (regex[1].patternType == REGEX_QUANTIFIER) {
            return matchQuantifier(regex, (regex + 1), text, matcher);

        } else if (regex[1].patternType == REGEX_STAR) {
            return matchStar(regex, (regex + 2), text, matcher);

        } else if (regex[1].patternType == REGEX_LAZY_STAR) {
            return matchStarLazy(regex, (regex + 2), text, matcher);

        } else if (regex[1].patternType == REGEX_PLUS) {
            return matchPlus(regex, (regex + 2), text, matcher);

        } else if (regex[1].patternType == REGEX_LAZY_PLUS) {
            return matchPlusLazy(regex, (regex + 2), text, matcher);

        } else if ((regex[0].patternType == REGEX_DOLLAR_END) && regex[1].patternType == REGEX_END_OF_PATTERN) {
            return (text[0] == END_LINE);
        }

        matcher.matchLength++;
    } while (text[0] != END_LINE && matchOne(regex++, *text++));

    matcher.matchLength = previousMatch;
    return false;

}
fn bool matchQuestionMark(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchQuestionMark")
{
    if (regex.patternType == REGEX_END_OF_PATTERN || matchPattern(pattern, matcher, text)) {
        return true;
    }

    if (*text && matchOne(regex, *text++)) {
        if (matchPattern(pattern, matcher, text)) {
            matcher.matchLength++;
            return true;
        }
    }
    return false;
}
fn bool matchQuantifier(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchQuantifier")
{
    int preLength = matcher.matchLength;
    ushort minQuantifier = pattern.minMaxQuantifiers[0];
    int maxQuantifier = pattern.minMaxQuantifiers[1] - minQuantifier;

    while (text[0] != END_LINE && minQuantifier > 0 && matchOne(regex, *text)) {
        matcher.matchLength++;
        minQuantifier--;
        text++;
    }

    if (minQuantifier > 0) {
        return false;
    }

    do {
        if (matchPattern(pattern + 1, matcher, text)) {
            return true;
        }
        matcher.matchLength++;
    } while (text[0] != END_LINE && maxQuantifier-- > 0 && matchOne(regex, *text++));

    matcher.matchLength = preLength;
    return false;
}

fn bool matchStar(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchStar")
{
    char *prePoint = text;
    while (text[0] != END_LINE && matchOne(regex, *text)) {
        matcher.matchLength++;
        text++;
    }

    if (matcher.matchLength == 0) {
        return false;
    }

    while (text >= prePoint) {
        if (matchPattern(pattern, matcher, text--)) {
            return true;
        }
        matcher.matchLength--;
    }
    return false;

}
fn bool matchStarLazy(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchStarLazy")
{
    int preLength = matcher.matchLength;

    do {
        if (matchPattern(pattern, matcher, text)) {
            return true;
        }
        matcher.matchLength++;
    } while (text[0] != END_LINE && matchOne(regex, *text++));

    matcher.matchLength = preLength;
    return false;
}

fn bool matchPlus(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchPlus")
{
    char *prePoint = text;
    while ((text[0] != END_LINE) && matchOne(regex, *text)) {
        matcher.matchLength++;
        text++;
    }

    while (text > prePoint) {   // match one or more
        if (matchPattern(pattern, matcher, text--)) {
            return true;
        }
        matcher.matchLength--;
    }
    matcher.matchLength = 0;
    return false;
}
fn bool matchPlusLazy(RegexNode *regex, RegexNode *pattern, char *text, Matcher *matcher) @extern("matchPlusLazy")
{
    while ((text[0] != END_LINE) && matchOne(regex, *text)) {
        matcher.matchLength++;
        text++;

        if (matchPattern(pattern, matcher, text)) {
            return true;
        }
    }
    matcher.matchLength--;
    return false;

}

fn bool matchOne(RegexNode *regex, char character) @extern("matchOne")
{
    switch (regex.patternType) {
        case REGEX_DOT:
            return isMatchingDot(character);
        case REGEX_CHAR_CLASS:
            return matchCharClass(character, regex.classCharPtr);
        case REGEX_INVERSE_CHAR_CLASS:
            return !matchCharClass(character, regex.classCharPtr);
        case REGEX_DIGIT:
            return ascii::is_digit(character);
        case REGEX_NOT_DIGIT:
            return !ascii::is_digit(character);
        case REGEX_ALPHA:
            return ascii::is_alnum(character);
        case REGEX_NOT_ALPHA:
            return !ascii::is_alnum(character);
        case REGEX_WHITESPACE:
            return ascii::is_space(character);
        case REGEX_NOT_WHITESPACE:
            return !ascii::is_space(character);
        case REGEX_REGULAR_CHAR:
            return (regex.regexChar == character);
        default:
            return false;
    }
}
fn  bool isMatchingDot(char character) @extern("isMatchingDot")
{
    if ($defined(REGEX_DOT_MATCH_NEWLINE) && (REGEX_DOT_MATCH_NEWLINE == true))
    {
        //(void) character;
        return true;
    }
    else
    {
        return (character != '\n' && character != '\r');
    }

}
fn bool matchCharClass(char character, char *metaCharString) @extern("matchCharClasses")
{
    do {
        if (isMatchingRange(character, metaCharString)) {
            return true;
        } else if (metaCharString[0] == '\\') { /* Escape-char: increment metaCharString-ptr and regexMatch on next char */
            metaCharString++;
            if (isMatchingMetaChar(character, metaCharString)) {
                return true;
            }
        } else if (character == metaCharString[0]) {
            return (character) == '-' ? (metaCharString[-1] == END_LINE) || (metaCharString[1] == END_LINE) : true;
        }
    } while (*metaCharString++ != END_LINE);

    return false;
}
fn bool isMatchingRange(char character, char *string) @extern("isMatchingRange")
{
    return ((character != '-')
            && (string[0] != END_LINE)
            && (string[0] != '-')
            && (string[1] == '-')
            && (string[2] != END_LINE)
            && ((character >= string[0]) && (character <= string[2])));
}
fn bool isMatchingMetaChar(char character, char *metaCharString) @extern("isMatchingMetaChar")
{
    char metaChar = metaCharString[0];
    switch (metaChar) {
        case 'd':
            return ascii::is_digit(character);
        case 'D':
            return !ascii::is_digit(character);
        case 'w':
            return ascii::is_alnum(character);
        case 'W':
            return !ascii::is_alnum(character);
        case 's':
            return ascii::is_space(character);
        case 'S':
            return !ascii::is_space(character);
        default:
            return (character == metaChar);
    }
}

