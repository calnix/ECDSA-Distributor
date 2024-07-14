## Use of 1/2 instead of bool or 1/0

When you want to store a true/false value, the first instinct is naturally to store it as a boolean. However, because the EVM stores boolean values as a uint8 type, which takes up two bytes, it is actually more expensive to access the value. This is because it EVM words are 32 bytes long, so extra logic is needed to tell the VM to parse a value that is smaller than standard.

The next instinct is to store false as uint256(0), and true as uint256(1). That, it turns out, incurs significant gas costs as well because there is a fixed fee associated with flipping a zero value to something else.

### From rareskills

Most important: avoid zero to one storage writes where possible
Initializing a storage variable is one of the most expensive operations a contract can do.

When a storage variable goes from zero to non-zero, the user must pay 22,100 gas total (20,000 gas for a zero to non-zero write and 2,100 for a cold storage access).

This is why the Openzeppelin reentrancy guard registers functions as active or not with 1 and 2 rather than 0 and 1. It only costs 5,000 gas to alter a storage variable from non-zero to non-zero.


## TESTING

