# regex-c3
regex libray in c3 language

Thi is a 1:1 translation of C Regex ( https://github.com/ximtech/Regex ) for learning purpose

demo:

```
import regex;
import std::io;
fn void main()
{
    Regex regex;
    regex::compile(&regex,"[Hh]ello [Ww]orld\\s*[!]?");
    
    if(!regex.isPatternValid)
    {
        io::printf("Error: %s\n",regex.errorMessage);
        
        return;
    }
    
    Matcher matcher=regex::match(&regex,"ahem.. 'hello world !' ..");
    io::printf("Is found: %s\n", matcher.isFound ? "Yes" : "No");
    io::printf("At index: %d\n", matcher.foundAtIndex);
    io::printf("Length: %d\n", matcher.matchLength);

}
        
```
