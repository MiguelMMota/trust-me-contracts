- whenever you create or edit a smart contract file, make sure the code is structured in this order: version, imports, interfaces, libraries contracts. Each contract must also be structured with elements in this order: errors, type declarations, state variables, events, modifiers, functions. Functions must be organised in this order: constructor, receive function (if it exists), fallback function (if it exists), external, public, internal, private, views, pure functions
- different sections inside the contract should be identified by a header in the following format:
/*//////////////////////////
       <section name>       
//////////////////////////*/
Make sure the section name has a little padding and is centered relative to the lines of "/" encapsulating it!