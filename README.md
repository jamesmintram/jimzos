# jimzos

Move StackFrame and hardware dependent context switching into aarch
Single threaded spinlock
- Build an auto-release mechanism?
- Detect context switch when spinlock held (panic)
- Recursive spinlock? (Counter?)
- Save, Disable + Restore interrupts

Proper init of the Kernel Allocator
How is the Kernel Allocator used? Globally accessible? USE A BIG KERNEL LOCK!

Page Frame Allocator
- Needs its own memory
- Gives pages to things
- Doesn't know anything about kernel allocator (things above it)

Bootstrap Kernel Allocator
- Relies on the Page Frame Allocator for its memory
- Build initial kernel page tables
-- As an address space that we can map ranges of memory into and build
---- Kernel vs Arch tables
-- How do we bootstrap the memory for this? [Special process for VM bootstrap?]


Build some better register access code? More readable? Safer?
