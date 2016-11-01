## better performance
At most, we are going to handle 2.67m or 30m reaches. So if we could find a good hash function to use against the inner join of catchment layer and flowline layer, the performance can be greatly increased compared to the agnostic inner join implementation in DB.

We can create a set of keys and use `dict.fromkeys(keys)` to pre-size python dictionary. Idea is from http://stackoverflow.com/questions/16256913/improving-performance-of-very-large-dictionary-in-python .
