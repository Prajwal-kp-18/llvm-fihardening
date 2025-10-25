/*
 * ============================================================================
 * Comprehensive Fault Injection Hardening Test
 * * This program tests all major hardening features:
 * - Control Flow Integrity (CFI)
 * - Memory bounds checking
 * - Stack protection
 * - Critical variable verification
 * - Branch hardening
 * - Return address protection
 * - Pointer integrity
 * - Array operations
 * - Complex data structures
 * - Recursive algorithms
 * - Function pointers
 * - State machines
 * * === NEW MODULES ADDED ===
 * - B-Tree (Complex pointer/array logic, recursion)
 * - Custom Heap Allocator (Metadata integrity, pointer arithmetic)
 * - Virtual Machine (CFI, stack protection, state machine)
 * - A* Pathfinding (Heap data structure, complex state)
 * - Lexer/Tokenizer (String processing, state machine)
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>     // For new modules
#include <limits.h>   // For new modules
#include <math.h>     // For new modules
#include <stddef.h>   // For new modules (offsetof)
#include <float.h>     // For FLT_MAX

// ============================================================================
// Global Defines for New Modules
// ============================================================================

// --- B-Tree Defines ---
#define B_TREE_DEGREE 3 // 't' - minimum degree (defines node size)

// --- Custom Allocator Defines ---
#define HEAP_SIZE (1024 * 64) // 64KB heap
#define ALLOC_MAGIC 0xDEADBEEF
#define MIN_BLOCK_SIZE (sizeof(HeapBlockHeader) + 8)

// --- VM Defines ---
#define VM_STACK_SIZE 256
#define VM_MEMORY_SIZE 1024
#define VM_PROGRAM_CAPACITY 1024

// --- A* Pathfinding Defines ---
#define ASTAR_GRID_WIDTH 20
#define ASTAR_GRID_HEIGHT 20

// --- Lexer Defines ---
#define LEXER_MAX_TOKEN_LEN 256

// ============================================================================
// Data Structures (Original)
// ============================================================================

typedef struct Node {
    int data;
    struct Node* next;
    struct Node* prev;
} Node;

typedef struct {
    int id;
    char name[64];
    double balance;
    int transaction_count;
} Account;

typedef struct {
    int vertices;
    int edges;
    int** adjacency_matrix;
} Graph;

typedef enum {
    STATE_IDLE,
    STATE_PROCESSING,
    STATE_VALIDATING,
    STATE_COMPLETE,
    STATE_ERROR
} SystemState;

// ============================================================================
// Mathematical Operations (with critical calculations)
// ============================================================================

// Fibonacci with multiple return paths (tests branch hardening)
int fibonacci(int n) {
    if (n <= 0) return 0;
    if (n == 1) return 1;
    if (n == 2) return 1;
    
    int result = fibonacci(n - 1) + fibonacci(n - 2);
    
    // Critical value verification point
    if (result < 0) {
        return -1;  // Overflow detection
    }
    
    return result;
}

// Prime number checker with multiple branches
int is_prime(int n) {
    if (n <= 1) return 0;
    if (n <= 3) return 1;
    if (n % 2 == 0 || n % 3 == 0) return 0;
    
    for (int i = 5; i * i <= n; i += 6) {
        if (n % i == 0 || n % (i + 2) == 0) {
            return 0;
        }
    }
    
    return 1;
}

// Matrix multiplication (memory intensive)
void matrix_multiply(int** A, int** B, int** C, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            C[i][j] = 0;
            for (int k = 0; k < n; k++) {
                C[i][j] += A[i][k] * B[k][j];
            }
        }
    }
}

// Fast exponentiation (recursive with critical values)
long long power_mod(long long base, long long exp, long long mod) {
    if (exp == 0) return 1;
    if (exp == 1) return base % mod;
    
    long long half = power_mod(base, exp / 2, mod);
    long long result = (half * half) % mod;
    
    if (exp % 2 == 1) {
        result = (result * base) % mod;
    }
    
    return result;
}

// ============================================================================
// Array and Memory Operations
// ============================================================================

// Bubble sort with bounds checking
void bubble_sort(int* arr, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            // Array access - bounds checking critical
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}

// Binary search with critical index calculations
int binary_search(int* arr, int n, int target) {
    int left = 0;
    int right = n - 1;
    
    while (left <= right) {
        // Critical: mid calculation can overflow
        int mid = left + (right - left) / 2;
        
        if (arr[mid] == target) {
            return mid;
        } else if (arr[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return -1;
}

// Array rotation (complex pointer arithmetic)
void rotate_array(int* arr, int n, int k) {
    k = k % n;
    if (k == 0) return;
    
    int* temp = (int*)malloc(k * sizeof(int));
    if (!temp) return;
    
    // Copy first k elements
    for (int i = 0; i < k; i++) {
        temp[i] = arr[i];
    }
    
    // Shift remaining elements
    for (int i = 0; i < n - k; i++) {
        arr[i] = arr[i + k];
    }
    
    // Copy back temp elements
    for (int i = 0; i < k; i++) {
        arr[n - k + i] = temp[i];
    }
    
    free(temp);
}

// ============================================================================
// Linked List Operations
// ============================================================================

Node* create_node(int data) {
    Node* node = (Node*)malloc(sizeof(Node));
    if (node) {
        node->data = data;
        node->next = NULL;
        node->prev = NULL;
    }
    return node;
}

// Insert at head with pointer integrity checks
Node* insert_head(Node* head, int data) {
    Node* new_node = create_node(data);
    if (!new_node) return head;
    
    if (head) {
        new_node->next = head;
        head->prev = new_node;
    }
    
    return new_node;
}

// Reverse linked list (complex pointer manipulation)
Node* reverse_list(Node* head) {
    Node* prev = NULL;
    Node* current = head;
    Node* next = NULL;
    
    while (current) {
        next = current->next;
        current->next = prev;
        current->prev = next;
        prev = current;
        current = next;
    }
    
    return prev;
}

// Detect cycle in linked list (Floyd's algorithm)
int has_cycle(Node* head) {
    if (!head) return 0;
    
    Node* slow = head;
    Node* fast = head;
    
    while (fast && fast->next) {
        slow = slow->next;
        fast = fast->next->next;
        
        if (slow == fast) {
            return 1;
        }
    }
    
    return 0;
}

// Merge two sorted linked lists
Node* merge_sorted_lists(Node* l1, Node* l2) {
    if (!l1) return l2;
    if (!l2) return l1;
    
    Node* result = NULL;
    
    if (l1->data <= l2->data) {
        result = l1;
        result->next = merge_sorted_lists(l1->next, l2);
    } else {
        result = l2;
        result->next = merge_sorted_lists(l1, l2->next);
    }
    
    return result;
}

// ============================================================================
// Graph Operations
// ============================================================================

Graph* create_graph(int vertices) {
    Graph* g = (Graph*)malloc(sizeof(Graph));
    if (!g) return NULL;
    
    g->vertices = vertices;
    g->edges = 0;
    g->adjacency_matrix = (int**)malloc(vertices * sizeof(int*));
    
    for (int i = 0; i < vertices; i++) {
        g->adjacency_matrix[i] = (int*)calloc(vertices, sizeof(int));
    }
    
    return g;
}

void add_edge(Graph* g, int u, int v) {
    if (!g || u >= g->vertices || v >= g->vertices) return;
    
    if (g->adjacency_matrix[u][v] == 0) {
        g->adjacency_matrix[u][v] = 1;
        g->adjacency_matrix[v][u] = 1;  // Undirected graph
        g->edges++;
    }
}

// DFS traversal with recursion
void dfs_util(Graph* g, int vertex, int* visited) {
    visited[vertex] = 1;
    
    for (int i = 0; i < g->vertices; i++) {
        if (g->adjacency_matrix[vertex][i] && !visited[i]) {
            dfs_util(g, i, visited);
        }
    }
}

int is_connected(Graph* g) {
    if (!g || g->vertices == 0) return 1;
    
    int* visited = (int*)calloc(g->vertices, sizeof(int));
    if (!visited) return 0;
    
    dfs_util(g, 0, visited);
    
    int connected = 1;
    for (int i = 0; i < g->vertices; i++) {
        if (!visited[i]) {
            connected = 0;
            break;
        }
    }
    
    free(visited);
    return connected;
}

// ============================================================================
// Banking System (State Machine with Critical Operations)
// ============================================================================

typedef struct {
    Account* accounts;
    int num_accounts;
    SystemState state;
    int error_count;
} BankingSystem;

BankingSystem* init_banking_system(int num_accounts) {
    BankingSystem* sys = (BankingSystem*)malloc(sizeof(BankingSystem));
    if (!sys) return NULL;
    
    sys->accounts = (Account*)calloc(num_accounts, sizeof(Account));
    sys->num_accounts = num_accounts;
    sys->state = STATE_IDLE;
    sys->error_count = 0;
    
    return sys;
}

int create_account(BankingSystem* sys, int id, const char* name, double initial_balance) {
    if (!sys || id >= sys->num_accounts || id < 0) {
        if (sys) sys->error_count++;
        return -1;
    }
    
    sys->state = STATE_PROCESSING;
    
    sys->accounts[id].id = id;
    strncpy(sys->accounts[id].name, name, 63);
    sys->accounts[id].name[63] = '\0';
    sys->accounts[id].balance = initial_balance;
    sys->accounts[id].transaction_count = 0;
    
    sys->state = STATE_VALIDATING;
    
    // Critical validation
    if (sys->accounts[id].balance < 0) {
        sys->state = STATE_ERROR;
        sys->error_count++;
        return -1;
    }
    
    sys->state = STATE_COMPLETE;
    return 0;
}

int transfer(BankingSystem* sys, int from_id, int to_id, double amount) {
    if (!sys || from_id >= sys->num_accounts || to_id >= sys->num_accounts) {
        if (sys) sys->error_count++;
        return -1;
    }
    
    if (from_id == to_id || amount <= 0) {
        sys->error_count++;
        return -1;
    }
    
    sys->state = STATE_PROCESSING;
    
    // Critical: Check sufficient balance
    if (sys->accounts[from_id].balance < amount) {
        sys->state = STATE_ERROR;
        sys->error_count++;
        return -1;
    }
    
    // Critical transaction - must be atomic
    double old_from_balance = sys->accounts[from_id].balance;
    double old_to_balance = sys->accounts[to_id].balance;
    
    sys->accounts[from_id].balance -= amount;
    sys->accounts[to_id].balance += amount;
    
    sys->state = STATE_VALIDATING;
    
    // Verify transaction integrity
    double total_before = old_from_balance + old_to_balance;
    double total_after = sys->accounts[from_id].balance + sys->accounts[to_id].balance;
    
    if (total_before != total_after) {
        // Rollback
        sys->accounts[from_id].balance = old_from_balance;
        sys->accounts[to_id].balance = old_to_balance;
        sys->state = STATE_ERROR;
        sys->error_count++;
        return -1;
    }
    
    sys->accounts[from_id].transaction_count++;
    sys->accounts[to_id].transaction_count++;
    
    sys->state = STATE_COMPLETE;
    return 0;
}

double get_total_assets(BankingSystem* sys) {
    if (!sys) return 0.0;
    
    double total = 0.0;
    for (int i = 0; i < sys->num_accounts; i++) {
        total += sys->accounts[i].balance;
    }
    
    return total;
}

// ============================================================================
// Cryptographic Operations (Critical Value Computations)
// ============================================================================

// Simple hash function with collision handling
unsigned long hash_string(const char* str) {
    unsigned long hash = 5381;
    int c;
    
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c;  // hash * 33 + c
    }
    
    return hash;
}

// Caesar cipher with bounds checking
void caesar_encrypt(char* text, int shift) {
    if (!text) return;
    
    shift = shift % 26;
    if (shift < 0) shift += 26;
    
    for (int i = 0; text[i] != '\0'; i++) {
        if (text[i] >= 'a' && text[i] <= 'z') {
            text[i] = 'a' + (text[i] - 'a' + shift) % 26;
        } else if (text[i] >= 'A' && text[i] <= 'Z') {
            text[i] = 'A' + (text[i] - 'A' + shift) % 26;
        }
    }
}

// XOR cipher (pointer operations)
void xor_encrypt(char* data, int len, const char* key, int key_len) {
    if (!data || !key || len <= 0 || key_len <= 0) return;
    
    for (int i = 0; i < len; i++) {
        data[i] ^= key[i % key_len];
    }
}

// ============================================================================
// Function Pointers and Callbacks (CFI Testing)
// ============================================================================

typedef int (*MathOperation)(int, int);

int add(int a, int b) { return a + b; }
int subtract(int a, int b) { return a - b; }
int multiply(int a, int b) { return a * b; }
int divide(int a, int b) { return b != 0 ? a / b : 0; }

int apply_operation(int a, int b, MathOperation op) {
    if (!op) return 0;
    return op(a, b);
}

// Calculator with function pointer array
int calculator(int a, int b, int operation) {
    MathOperation ops[] = {add, subtract, multiply, divide};
    
    if (operation < 0 || operation > 3) {
        return 0;
    }
    
    return ops[operation](a, b);
}

// ============================================================================
// String Processing (Memory and Bounds Checking)
// ============================================================================

// String reversal in-place
void reverse_string(char* str) {
    if (!str) return;
    
    int len = strlen(str);
    for (int i = 0; i < len / 2; i++) {
        char temp = str[i];
        str[i] = str[len - 1 - i];
        str[len - 1 - i] = temp;
    }
}

// Pattern matching (KMP algorithm)
int kmp_search(const char* text, const char* pattern) {
    if (!text || !pattern) return -1;
    
    int n = strlen(text);
    int m = strlen(pattern);
    
    if (m == 0) return 0;
    if (n < m) return -1;
    
    // Build LPS array
    int* lps = (int*)calloc(m, sizeof(int));
    if (!lps) return -1;
    
    int len = 0;
    int i = 1;
    
    while (i < m) {
        if (pattern[i] == pattern[len]) {
            len++;
            lps[i] = len;
            i++;
        } else {
            if (len != 0) {
                len = lps[len - 1];
            } else {
                lps[i] = 0;
                i++;
            }
        }
    }
    
    // Search for pattern
    i = 0;
    int j = 0;
    int result = -1;
    
    while (i < n) {
        if (pattern[j] == text[i]) {
            i++;
            j++;
        }
        
        if (j == m) {
            result = i - j;
            break;
        } else if (i < n && pattern[j] != text[i]) {
            if (j != 0) {
                j = lps[j - 1];
            } else {
                i++;
            }
        }
    }
    
    free(lps);
    return result;
}

// ============================================================================
// NEW MODULE: B-Tree (Complex Data Structure)
// ============================================================================

// B-Tree Node Structure
typedef struct BTreeNode {
    int* keys;
    struct BTreeNode** children;
    int n;       // Current number of keys
    int t;       // Minimum degree (t = B_TREE_DEGREE)
    int leaf;    // 1 if leaf, 0 if internal
} BTreeNode;

// Forward declaration for btree_delete
void btree_delete(BTreeNode* node, int k);

// B-Tree Structure
typedef struct {
    BTreeNode* root;
    int t;
} BTree;

// Create a new B-Tree node
BTreeNode* btree_create_node(int t, int leaf) {
    BTreeNode* node = (BTreeNode*)malloc(sizeof(BTreeNode));
    if (!node) return NULL;
    
    node->t = t;
    node->leaf = leaf;
    
    // Max keys = 2*t - 1
    // Max children = 2*t
    node->keys = (int*)malloc((2 * t - 1) * sizeof(int));
    node->children = (BTreeNode**)malloc((2 * t) * sizeof(BTreeNode*));
    node->n = 0;
    
    return node;
}

// Create an empty B-Tree
BTree* btree_create() {
    BTree* tree = (BTree*)malloc(sizeof(BTree));
    if (!tree) return NULL;
    
    tree->t = B_TREE_DEGREE;
    BTreeNode* root = btree_create_node(tree->t, 1);
    if (!root) {
        free(tree);
        return NULL;
    }
    
    tree->root = root;
    return tree;
}

// Traverse the B-Tree (in-order)
void btree_traverse(BTreeNode* node) {
    if (!node) return;
    
    int i;
    for (i = 0; i < node->n; i++) {
        if (!node->leaf) {
            btree_traverse(node->children[i]);
        }
        printf(" %d", node->keys[i]);
    }
    
    if (!node->leaf) {
        btree_traverse(node->children[i]);
    }
}

// Search for a key in the B-Tree
BTreeNode* btree_search(BTreeNode* node, int key) {
    if (!node) return NULL;
    
    int i = 0;
    while (i < node->n && key > node->keys[i]) {
        i++;
    }
    
    if (i < node->n && node->keys[i] == key) {
        return node;
    }
    
    if (node->leaf) {
        return NULL;
    }
    
    // Critical: recursive call, must be CFI protected
    return btree_search(node->children[i], key);
}

// Split a full child node y of this node
// y is at index i in children[]
void btree_split_child(BTreeNode* x, int i) {
    int t = x->t;
    BTreeNode* y = x->children[i];
    
    // Create new node z
    BTreeNode* z = btree_create_node(t, y->leaf);
    z->n = t - 1;
    
    // Copy last (t-1) keys from y to z
    for (int j = 0; j < t - 1; j++) {
        z->keys[j] = y->keys[j + t];
    }
    
    // Copy last t children from y to z (if not leaf)
    if (!y->leaf) {
        for (int j = 0; j < t; j++) {
            z->children[j] = y->children[j + t];
        }
    }
    
    y->n = t - 1;
    
    // Shift children in x to make space for z
    for (int j = x->n; j >= i + 1; j--) {
        x->children[j + 1] = x->children[j];
    }
    
    // Link new child z to x
    x->children[i + 1] = z;
    
    // Shift keys in x to make space for y's middle key
    for (int j = x->n - 1; j >= i; j--) {
        x->keys[j + 1] = x->keys[j];
    }
    
    // Copy middle key of y to x
    x->keys[i] = y->keys[t - 1];
    x->n++;
}

// Insert a key into a non-full node
void btree_insert_non_full(BTreeNode* x, int key) {
    int i = x->n - 1;
    
    if (x->leaf) {
        // Find location and shift keys
        while (i >= 0 && x->keys[i] > key) {
            x->keys[i + 1] = x->keys[i];
            i--;
        }
        x->keys[i + 1] = key;
        x->n++;
    } else {
        // Find the child to insert into
        while (i >= 0 && x->keys[i] > key) {
            i--;
        }
        i++;
        
        // Check if child is full
        if (x->children[i]->n == 2 * x->t - 1) {
            btree_split_child(x, i);
            
            // Middle key moves up, decide which child to use
            if (x->keys[i] < key) {
                i++;
            }
        }
        btree_insert_non_full(x->children[i], key);
    }
}

// Insert a key into the B-Tree
void btree_insert(BTree* tree, int key) {
    BTreeNode* r = tree->root;
    
    // If root is full
    if (r->n == 2 * tree->t - 1) {
        // Create new root
        BTreeNode* s = btree_create_node(tree->t, 0); // Not a leaf
        tree->root = s;
        s->children[0] = r;
        
        // Split the old root
        btree_split_child(s, 0);
        
        // New root has 1 key, 2 children. Decide which child to use.
        int i = 0;
        if (s->keys[0] < key) {
            i++;
        }
        btree_insert_non_full(s->children[i], key);
    } else {
        btree_insert_non_full(r, key);
    }
}

// Find index of the first key >= k
int btree_find_key(BTreeNode* node, int k) {
    int idx = 0;
    while (idx < node->n && node->keys[idx] < k)
        ++idx;
    return idx;
}

// Get predecessor key
int btree_get_predecessor(BTreeNode* node) {
    BTreeNode* curr = node;
    while (!curr->leaf)
        curr = curr->children[curr->n];
    return curr->keys[curr->n - 1];
}

// Get successor key
int btree_get_successor(BTreeNode* node) {
    BTreeNode* curr = node;
    while (!curr->leaf)
        curr = curr->children[0];
    return curr->keys[0];
}

// Fill child node at idx (if it has t-1 keys)
void btree_fill(BTreeNode* node, int idx) {
    // Borrow from previous sibling
    if (idx != 0 && node->children[idx - 1]->n >= node->t) {
        BTreeNode* child = node->children[idx];
        BTreeNode* sibling = node->children[idx - 1];
        
        for (int i = child->n - 1; i >= 0; --i)
            child->keys[i + 1] = child->keys[i];
        
        if (!child->leaf) {
            for (int i = child->n; i >= 0; --i)
                child->children[i + 1] = child->children[i];
        }
        
        child->keys[0] = node->keys[idx - 1];
        
        if (!child->leaf)
            child->children[0] = sibling->children[sibling->n];
        
        node->keys[idx - 1] = sibling->keys[sibling->n - 1];
        
        child->n++;
        sibling->n--;
    }
    // Borrow from next sibling
    else if (idx != node->n && node->children[idx + 1]->n >= node->t) {
        BTreeNode* child = node->children[idx];
        BTreeNode* sibling = node->children[idx + 1];
        
        child->keys[child->n] = node->keys[idx];
        
        if (!child->leaf)
            child->children[child->n + 1] = sibling->children[0];
        
        node->keys[idx] = sibling->keys[0];
        
        for (int i = 1; i < sibling->n; ++i)
            sibling->keys[i - 1] = sibling->keys[i];
        
        if (!sibling->leaf) {
            for (int i = 1; i <= sibling->n; ++i)
                sibling->children[i - 1] = sibling->children[i];
        }
        
        child->n++;
        sibling->n--;
    }
    // Merge child with a sibling
    else {
        if (idx != node->n) { // Merge with next sibling
            BTreeNode* child = node->children[idx];
            BTreeNode* sibling = node->children[idx + 1];
            
            child->keys[node->t - 1] = node->keys[idx];
            
            for (int i = 0; i < sibling->n; ++i)
                child->keys[i + node->t] = sibling->keys[i];
            
            if (!child->leaf) {
                for (int i = 0; i <= sibling->n; ++i)
                    child->children[i + node->t] = sibling->children[i];
            }
            
            for (int i = idx + 1; i < node->n; ++i)
                node->keys[i - 1] = node->keys[i];
            
            for (int i = idx + 2; i <= node->n; ++i)
                node->children[i - 1] = node->children[i];
            
            child->n += sibling->n + 1;
            node->n--;
            
            free(sibling->keys);
            free(sibling->children);
            free(sibling);
        } else { // Merge with previous sibling
            BTreeNode* child = node->children[idx];
            BTreeNode* sibling = node->children[idx - 1];
            
            sibling->keys[node->t - 1] = node->keys[idx - 1];
            
            for (int i = 0; i < child->n; ++i)
                sibling->keys[i + node->t] = child->keys[i];
            
            if (!child->leaf) {
                for (int i = 0; i <= child->n; ++i)
                    sibling->children[i + node->t] = child->children[i];
            }
            
            for (int i = idx; i < node->n; ++i)
                node->keys[i - 1] = node->keys[i];
            
            for (int i = idx + 1; i <= node->n; ++i)
                node->children[i - 1] = node->children[i];
            
            sibling->n += child->n + 1;
            node->n--;
            
            free(child->keys);
            free(child->children);
            free(child);
        }
    }
}

// Delete from a leaf node
void btree_delete_from_leaf(BTreeNode* node, int idx) {
    for (int i = idx + 1; i < node->n; ++i)
        node->keys[i - 1] = node->keys[i];
    node->n--;
}

// Delete from a non-leaf node
void btree_delete_from_non_leaf(BTreeNode* node, int idx) {
    int k = node->keys[idx];
    
    if (node->children[idx]->n >= node->t) {
        int pred = btree_get_predecessor(node->children[idx]);
        node->keys[idx] = pred;
        btree_delete(node->children[idx], pred);
    } else if (node->children[idx + 1]->n >= node->t) {
        int succ = btree_get_successor(node->children[idx + 1]);
        node->keys[idx] = succ;
        btree_delete(node->children[idx + 1], succ);
    } else {
        // Merge child[idx] and child[idx+1]
        BTreeNode* child = node->children[idx];
        BTreeNode* sibling = node->children[idx + 1];
        
        child->keys[node->t - 1] = node->keys[idx];
        
        for (int i = 0; i < sibling->n; ++i)
            child->keys[i + node->t] = sibling->keys[i];
        
        if (!child->leaf) {
            for (int i = 0; i <= sibling->n; ++i)
                child->children[i + node->t] = sibling->children[i];
        }
        
        for (int i = idx + 1; i < node->n; ++i)
            node->keys[i - 1] = node->keys[i];
        
        for (int i = idx + 2; i <= node->n; ++i)
            node->children[i - 1] = node->children[i];
        
        child->n += sibling->n + 1;
        node->n--;
        
        free(sibling->keys);
        free(sibling->children);
        free(sibling);
        
        btree_delete(child, k);
    }
}

// Delete key from subtree rooted at node
void btree_delete(BTreeNode* node, int k) {
    int idx = btree_find_key(node, k);
    
    if (idx < node->n && node->keys[idx] == k) {
        if (node->leaf)
            btree_delete_from_leaf(node, idx);
        else
            btree_delete_from_non_leaf(node, idx);
    } else {
        if (node->leaf) {
            // Key not in tree
            return;
        }
        
        int is_last_child = (idx == node->n);
        
        if (node->children[idx]->n < node->t)
            btree_fill(node, idx);
        
        if (is_last_child && idx > node->n)
            btree_delete(node->children[idx - 1], k);
        else
            btree_delete(node->children[idx], k);
    }
}

// Wrapper for B-Tree delete
void btree_delete_key(BTree* tree, int k) {
    if (!tree || !tree->root) return;
    
    btree_delete(tree->root, k);
    
    // If root becomes empty
    if (tree->root->n == 0) {
        BTreeNode* old_root = tree->root;
        if (tree->root->leaf) {
            // Tree is now empty
        } else {
            tree->root = tree->root->children[0];
            free(old_root->keys);
            free(old_root->children);
            free(old_root);
        }
    }
}

// Destroy B-Tree
void btree_destroy(BTreeNode* node) {
    if (!node) return;
    if (!node->leaf) {
        for (int i = 0; i <= node->n; i++) {
            btree_destroy(node->children[i]);
        }
    }
    free(node->keys);
    free(node->children);
    free(node);
}

// ============================================================================
// NEW MODULE: Custom Heap Allocator (Memory Integrity)
// ============================================================================

// Header for each memory block (critical metadata)
typedef struct HeapBlockHeader {
    size_t size;                   // Size of the data block (not including header)
    int is_free;                   // 1 if free, 0 if allocated
    uint32_t magic;                // Magic number (e.g., 0xDEADBEEF)
    struct HeapBlockHeader* next;  // Next block in memory
    struct HeapBlockHeader* prev;  // Previous block in memory
    struct HeapBlockHeader* next_free; // Next block in free list
    struct HeapBlockHeader* prev_free; // Previous block in free list
} HeapBlockHeader;

// The heap memory
static unsigned char g_heap_memory[HEAP_SIZE];
static HeapBlockHeader* g_free_list_head = NULL;
static int g_heap_initialized = 0;

// Get the header from a data pointer
HeapBlockHeader* get_header_from_ptr(void* ptr) {
    return (HeapBlockHeader*)((unsigned char*)ptr - sizeof(HeapBlockHeader));
}

// Get the data pointer from a header
void* get_ptr_from_header(HeapBlockHeader* header) {
    return (void*)((unsigned char*)header + sizeof(HeapBlockHeader));
}

// Initialize the heap
void heap_init() {
    if (g_heap_initialized) return;
    
    g_free_list_head = (HeapBlockHeader*)g_heap_memory;
    g_free_list_head->size = HEAP_SIZE - sizeof(HeapBlockHeader);
    g_free_list_head->is_free = 1;
    g_free_list_head->magic = ALLOC_MAGIC;
    g_free_list_head->next = NULL;
    g_free_list_head->prev = NULL;
    g_free_list_head->next_free = NULL;
    g_free_list_head->prev_free = NULL;
    
    g_heap_initialized = 1;
}

// Remove a block from the free list
void remove_from_free_list(HeapBlockHeader* block) {
    if (block->prev_free) {
        block->prev_free->next_free = block->next_free;
    } else {
        g_free_list_head = block->next_free;
    }
    if (block->next_free) {
        block->next_free->prev_free = block->prev_free;
    }
    block->prev_free = NULL;
    block->next_free = NULL;
}

// Add a block to the front of the free list
void add_to_free_list(HeapBlockHeader* block) {
    block->next_free = g_free_list_head;
    block->prev_free = NULL;
    if (g_free_list_head) {
        g_free_list_head->prev_free = block;
    }
    g_free_list_head = block;
}

// Split a block if it's larger than needed
void split_block(HeapBlockHeader* block, size_t requested_size) {
    size_t remaining_size = block->size - requested_size;
    
    // Check if remaining space is large enough for a new block
    if (remaining_size >= MIN_BLOCK_SIZE) {
        // Create new header for the remaining free block
        HeapBlockHeader* new_block = (HeapBlockHeader*)((unsigned char*)get_ptr_from_header(block) + requested_size);
        new_block->size = remaining_size - sizeof(HeapBlockHeader);
        new_block->is_free = 1;
        new_block->magic = ALLOC_MAGIC;
        
        // Link new block into the main memory list
        new_block->next = block->next;
        new_block->prev = block;
        if (block->next) {
            block->next->prev = new_block;
        }
        block->next = new_block;
        
        // Set original block size
        block->size = requested_size;
        
        // Add new block to free list
        add_to_free_list(new_block);
    }
}

// Find a free block (First-Fit)
HeapBlockHeader* find_first_fit(size_t size) {
    HeapBlockHeader* current = g_free_list_head;
    while (current) {
        // Critical: Check metadata integrity
        if (current->magic != ALLOC_MAGIC) {
            fprintf(stderr, "Heap corruption detected in find_first_fit!\n");
            return NULL; 
        }
        if (current->is_free && current->size >= size) {
            return current;
        }
        current = current->next_free;
    }
    return NULL;
}

// Custom malloc
void* custom_malloc(size_t size) {
    if (!g_heap_initialized) {
        heap_init();
    }
    
    if (size == 0) return NULL;
    
    // Align size to 8 bytes
    size = (size + 7) & ~7;
    
    HeapBlockHeader* block = find_first_fit(size);
    
    if (block) {
        // Found a block
        remove_from_free_list(block);
        block->is_free = 0;
        
        // Split the block if it's much larger
        split_block(block, size);
        
        return get_ptr_from_header(block);
    }
    
    // No block found
    return NULL;
}

// Coalesce (merge) free blocks
HeapBlockHeader* coalesce_blocks(HeapBlockHeader* block) {
    // Check next block
    if (block->next && block->next->is_free) {
        // Critical: Metadata check
        if (block->next->magic != ALLOC_MAGIC) {
            fprintf(stderr, "Heap corruption (next block) detected in coalesce!\n");
            return block;
        }
        
        remove_from_free_list(block->next);
        
        block->size += block->next->size + sizeof(HeapBlockHeader);
        block->next = block->next->next;
        if (block->next) {
            block->next->prev = block;
        }
    }
    
    // Check previous block
    if (block->prev && block->prev->is_free) {
        // Critical: Metadata check
        if (block->prev->magic != ALLOC_MAGIC) {
            fprintf(stderr, "Heap corruption (prev block) detected in coalesce!\n");
            return block;
        }
        
        block = block->prev;
        remove_from_free_list(block);
        
        block->size += block->next->size + sizeof(HeapBlockHeader);
        block->next = block->next->next;
        if (block->next) {
            block->next->prev = block;
        }
    }
    
    return block;
}

// Custom free
void custom_free(void* ptr) {
    if (ptr == NULL) return;
    
    HeapBlockHeader* block = get_header_from_ptr(ptr);
    
    // Critical: Check magic number
    if (block->magic != ALLOC_MAGIC) {
        fprintf(stderr, "Heap corruption detected in free: invalid magic number!\n");
        return;
    }
    
    // Critical: Check for double free
    if (block->is_free) {
        fprintf(stderr, "Heap error: Double free detected!\n");
        return;
    }
    
    block->is_free = 1;
    
    // Coalesce with neighbors
    block = coalesce_blocks(block);
    
    // Add (potentially new, larger) block to free list
    add_to_free_list(block);
}

// Custom calloc
void* custom_calloc(size_t num, size_t size) {
    size_t total_size = num * size;
    
    // Check for overflow
    if (num != 0 && total_size / num != size) {
        return NULL;
    }
    
    void* ptr = custom_malloc(total_size);
    if (ptr) {
        // Zero out the memory
        memset(ptr, 0, total_size);
    }
    return ptr;
}

// Custom realloc
void* custom_realloc(void* ptr, size_t new_size) {
    if (ptr == NULL) {
        return custom_malloc(new_size);
    }
    
    if (new_size == 0) {
        custom_free(ptr);
        return NULL;
    }
    
    HeapBlockHeader* block = get_header_from_ptr(ptr);
    if (block->magic != ALLOC_MAGIC) {
         fprintf(stderr, "Heap corruption detected in realloc!\n");
         return NULL;
    }
    
    // Align new size
    new_size = (new_size + 7) & ~7;
    
    if (block->size >= new_size) {
        // Can shrink in place
        split_block(block, new_size);
        return ptr;
    }
    
    // Need to allocate new block and copy
    void* new_ptr = custom_malloc(new_size);
    if (new_ptr) {
        memcpy(new_ptr, ptr, block->size);
        custom_free(ptr);
    }
    
    return new_ptr;
}

// Get heap stats (for testing)
void heap_get_stats(size_t* total_free, size_t* total_used, int* free_blocks) {
    *total_free = 0;
    *total_used = 0;
    *free_blocks = 0;
    
    HeapBlockHeader* current = (HeapBlockHeader*)g_heap_memory;
    while (current) {
        if (current->magic != ALLOC_MAGIC) {
            fprintf(stderr, "Heap corruption detected during stats collection!\n");
            return;
        }
        
        if (current->is_free) {
            *total_free += current->size;
            (*free_blocks)++;
        } else {
            *total_used += current->size;
        }
        
        current = current->next;
    }
}


// ============================================================================
// NEW MODULE: Simple Virtual Machine (CFI / Stack Protection)
// ============================================================================

typedef enum {
    OP_HALT,    // 0: Stop execution
    OP_PUSH,    // 1: PUSH <value>
    OP_POP,     // 2: POP
    OP_ADD,     // 3: ADD (a, b -> a+b)
    OP_SUB,     // 4: SUB (a, b -> a-b)
    OP_MUL,     // 5: MUL (a, b -> a*b)
    OP_DIV,     // 6: DIV (a, b -> a/b)
    OP_MOD,     // 7: MOD (a, b -> a%b)
    OP_CMP,     // 8: CMP (a, b) -> sets flags
    OP_JMP,     // 9: JMP <addr>
    OP_JZ,      // 10: JMP if Zero
    OP_JNZ,     // 11: JMP if Not Zero
    OP_JG,      // 12: JMP if Greater
    OP_JL,      // 13: JMP if Less
    OP_CALL,    // 14: CALL <addr>
    OP_RET,     // 15: RET
    OP_LOAD,    // 16: LOAD <addr> (push mem[addr])
    OP_STORE,   // 17: STORE <addr> (pop -> mem[addr])
    OP_PRINT,   // 18: PRINT (pop and print)
    OP_NOP      // 19: No operation
} OpCode;

typedef struct {
    int32_t stack[VM_STACK_SIZE];
    int32_t memory[VM_MEMORY_SIZE];
    int32_t program[VM_PROGRAM_CAPACITY];
    int program_size;
    
    // Critical registers (state)
    int pc; // Program Counter
    int sp; // Stack Pointer
    
    // Flags
    int zero_flag;
    int sign_flag;
    
    int halted;
} VM;

VM* vm_create() {
    // Use our custom allocator
    VM* vm = (VM*)custom_malloc(sizeof(VM));
    if (!vm) return NULL;
    
    memset(vm, 0, sizeof(VM));
    vm->sp = -1; // Stack is empty
    vm->pc = 0;
    vm->halted = 0;
    
    return vm;
}

void vm_destroy(VM* vm) {
    if (vm) {
        // Use our custom allocator
        custom_free(vm);
    }
}

int vm_load_program(VM* vm, int32_t* program_data, int size) {
    if (!vm || !program_data || size > VM_PROGRAM_CAPACITY) {
        return -1;
    }
    
    memcpy(vm->program, program_data, size * sizeof(int32_t));
    vm->program_size = size;
    vm->pc = 0;
    vm->sp = -1;
    vm->halted = 0;
    
    return 0;
}

// --- VM Stack Operations (Critical: bounds checking) ---
int vm_push(VM* vm, int32_t value) {
    if (vm->sp >= VM_STACK_SIZE - 1) {
        fprintf(stderr, "VM Error: Stack Overflow\n");
        vm->halted = 1;
        return -1;
    }
    vm->stack[++(vm->sp)] = value;
    return 0;
}

int32_t vm_pop(VM* vm) {
    if (vm->sp < 0) {
        fprintf(stderr, "VM Error: Stack Underflow\n");
        vm->halted = 1;
        return 0;
    }
    return vm->stack[(vm->sp)--];
}

// --- VM Memory Operations (Critical: bounds checking) ---
int vm_store(VM* vm, int32_t addr, int32_t value) {
    if (addr < 0 || addr >= VM_MEMORY_SIZE) {
        fprintf(stderr, "VM Error: Memory Store Out of Bounds (addr %d)\n", addr);
        vm->halted = 1;
        return -1;
    }
    vm->memory[addr] = value;
    return 0;
}

int32_t vm_load(VM* vm, int32_t addr) {
     if (addr < 0 || addr >= VM_MEMORY_SIZE) {
        fprintf(stderr, "VM Error: Memory Load Out of Bounds (addr %d)\n", addr);
        vm->halted = 1;
        return 0;
    }
    return vm->memory[addr];
}

// --- VM Execution Cycle ---
int vm_execute_instruction(VM* vm) {
    // Critical: Check Program Counter bounds (CFI)
    if (vm->pc < 0 || vm->pc >= vm->program_size) {
        fprintf(stderr, "VM Error: Program Counter Out of Bounds (PC=%d)\n", vm->pc);
        vm->halted = 1;
        return -1;
    }
    
    OpCode op = (OpCode)vm->program[vm->pc];
    int32_t a, b, addr, value;
    
    // This switch is a prime target for branch hardening
    switch (op) {
        case OP_HALT:
            vm->halted = 1;
            break;
            
        case OP_PUSH:
            vm->pc++;
            value = vm->program[vm->pc];
            vm_push(vm, value);
            break;
            
        case OP_POP:
            vm_pop(vm);
            break;
            
        case OP_ADD:
            b = vm_pop(vm);
            a = vm_pop(vm);
            vm_push(vm, a + b);
            break;
            
        case OP_SUB:
            b = vm_pop(vm);
            a = vm_pop(vm);
            vm_push(vm, a - b);
            break;
            
        case OP_MUL:
            b = vm_pop(vm);
            a = vm_pop(vm);
            vm_push(vm, a * b);
            break;
            
        case OP_DIV:
            b = vm_pop(vm);
            a = vm_pop(vm);
            if (b == 0) {
                fprintf(stderr, "VM Error: Division by zero\n");
                vm->halted = 1;
            } else {
                vm_push(vm, a / b);
            }
            break;

        case OP_MOD:
            b = vm_pop(vm);
            a = vm_pop(vm);
            if (b == 0) {
                fprintf(stderr, "VM Error: Modulo by zero\n");
                vm->halted = 1;
            } else {
                vm_push(vm, a % b);
            }
            break;

        case OP_CMP:
            b = vm_pop(vm);
            a = vm_pop(vm);
            vm->zero_flag = (a == b);
            vm->sign_flag = (a < b);
            break;
            
        case OP_JMP:
            vm->pc++;
            addr = vm->program[vm->pc];
            vm->pc = addr - 1; // -1 because PC increments at end
            break;
            
        case OP_JZ:
            vm->pc++;
            addr = vm->program[vm->pc];
            if (vm->zero_flag) {
                vm->pc = addr - 1;
            }
            break;
            
        case OP_JNZ:
            vm->pc++;
            addr = vm->program[vm->pc];
            if (!vm->zero_flag) {
                vm->pc = addr - 1;
            }
            break;

        case OP_JG:
            vm->pc++;
            addr = vm->program[vm->pc];
            if (!vm->zero_flag && !vm->sign_flag) {
                vm->pc = addr - 1;
            }
            break;
            
        case OP_JL:
            vm->pc++;
            addr = vm->program[vm->pc];
            if (vm->sign_flag) {
                vm->pc = addr - 1;
            }
            break;
            
        case OP_CALL:
            vm->pc++;
            addr = vm->program[vm->pc];
            // Critical: Return address protection
            vm_push(vm, vm->pc + 1); // Push return address
            vm->pc = addr - 1; // Jump to function
            break;
            
        case OP_RET:
            // Critical: Return address protection
            addr = vm_pop(vm);
            vm->pc = addr - 1;
            break;
            
        case OP_LOAD:
            vm->pc++;
            addr = vm->program[vm->pc];
            value = vm_load(vm, addr);
            vm_push(vm, value);
            break;
            
        case OP_STORE:
            vm->pc++;
            addr = vm->program[vm->pc];
            value = vm_pop(vm);
            vm_store(vm, addr, value);
            break;
            
        case OP_PRINT:
            value = vm_pop(vm);
            printf("VM Output: %d\n", value);
            break;
            
        case OP_NOP:
            // Do nothing
            break;
            
        default:
            fprintf(stderr, "VM Error: Unknown OpCode %d\n", op);
            vm->halted = 1;
            break;
    }
    
    vm->pc++;
    return 0;
}

int vm_run(VM* vm) {
    if (!vm) return -1;
    
    while (!vm->halted) {
        if (vm_execute_instruction(vm) != 0) {
            break;
        }
    }
    
    if (vm->sp != -1) {
        printf("VM Warning: Stack not empty on halt (SP=%d)\n", vm->sp);
    }
    
    return vm->halted ? 0 : -1;
}

// ============================================================================
// NEW MODULE: A* Pathfinding (Graph/Heap Algorithm)
// ============================================================================

// --- Min-Heap for A* ---
typedef struct {
    int x, y;
    float f_cost;
} MinHeapAStarNode;

typedef struct {
    MinHeapAStarNode* nodes;
    int size;
    int capacity;
    // pos_map maps (x,y) to heap index for decrease_key
    int* pos_map; 
} MinHeapAStar;

MinHeapAStar* min_heap_astar_create(int capacity) {
    MinHeapAStar* heap = (MinHeapAStar*)custom_malloc(sizeof(MinHeapAStar));
    heap->nodes = (MinHeapAStarNode*)custom_malloc(capacity * sizeof(MinHeapAStarNode));
    heap->pos_map = (int*)custom_malloc(ASTAR_GRID_WIDTH * ASTAR_GRID_HEIGHT * sizeof(int));
    heap->size = 0;
    heap->capacity = capacity;
    
    for (int i = 0; i < ASTAR_GRID_WIDTH * ASTAR_GRID_HEIGHT; i++) {
        heap->pos_map[i] = -1;
    }
    
    return heap;
}

int min_heap_astar_pos_index(int x, int y) {
    return y * ASTAR_GRID_WIDTH + x;
}

void min_heap_astar_swap(MinHeapAStar* heap, int i, int j) {
    MinHeapAStarNode temp = heap->nodes[i];
    heap->nodes[i] = heap->nodes[j];
    heap->nodes[j] = temp;
    
    // Update position map
    heap->pos_map[min_heap_astar_pos_index(heap->nodes[i].x, heap->nodes[i].y)] = i;
    heap->pos_map[min_heap_astar_pos_index(heap->nodes[j].x, heap->nodes[j].y)] = j;
}

void min_heap_astar_heapify_down(MinHeapAStar* heap, int idx) {
    int smallest = idx;
    int left = 2 * idx + 1;
    int right = 2 * idx + 2;
    
    if (left < heap->size && heap->nodes[left].f_cost < heap->nodes[smallest].f_cost)
        smallest = left;
    
    if (right < heap->size && heap->nodes[right].f_cost < heap->nodes[smallest].f_cost)
        smallest = right;
    
    if (smallest != idx) {
        min_heap_astar_swap(heap, idx, smallest);
        min_heap_astar_heapify_down(heap, smallest);
    }
}

void min_heap_astar_heapify_up(MinHeapAStar* heap, int idx) {
    int parent = (idx - 1) / 2;
    while (idx > 0 && heap->nodes[idx].f_cost < heap->nodes[parent].f_cost) {
        min_heap_astar_swap(heap, idx, parent);
        idx = parent;
        parent = (idx - 1) / 2;
    }
}

MinHeapAStarNode min_heap_astar_extract_min(MinHeapAStar* heap) {
    if (heap->size == 0) return (MinHeapAStarNode){-1, -1, -1.0f};
    
    MinHeapAStarNode root = heap->nodes[0];
    heap->nodes[0] = heap->nodes[heap->size - 1];
    heap->size--;
    
    heap->pos_map[min_heap_astar_pos_index(root.x, root.y)] = -1;
    if(heap->size > 0)
        heap->pos_map[min_heap_astar_pos_index(heap->nodes[0].x, heap->nodes[0].y)] = 0;
    
    min_heap_astar_heapify_down(heap, 0);
    
    return root;
}

void min_heap_astar_insert(MinHeapAStar* heap, int x, int y, float f_cost) {
    if (heap->size == heap->capacity) {
        fprintf(stderr, "A* Min-Heap full!\n");
        return;
    }
    
    int i = heap->size;
    heap->nodes[i] = (MinHeapAStarNode){x, y, f_cost};
    heap->pos_map[min_heap_astar_pos_index(x, y)] = i;
    heap->size++;
    
    min_heap_astar_heapify_up(heap, i);
}

void min_heap_astar_decrease_key(MinHeapAStar* heap, int x, int y, float new_f_cost) {
    int i = heap->pos_map[min_heap_astar_pos_index(x, y)];
    if (i == -1 || i >= heap->size) return; 
    
    heap->nodes[i].f_cost = new_f_cost;
    min_heap_astar_heapify_up(heap, i);
}

int min_heap_astar_is_empty(MinHeapAStar* heap) {
    return heap->size == 0;
}

int min_heap_astar_is_in_heap(MinHeapAStar* heap, int x, int y) {
    return heap->pos_map[min_heap_astar_pos_index(x, y)] != -1;
}

void min_heap_astar_destroy(MinHeapAStar* heap) {
    custom_free(heap->nodes);
    custom_free(heap->pos_map);
    custom_free(heap);
}


// --- A* Algorithm ---
typedef struct {
    int x, y;
} AStarPoint;

typedef struct {
    int grid[ASTAR_GRID_HEIGHT][ASTAR_GRID_WIDTH]; // 0=walkable, 1=obstacle
} AStarMap;

typedef struct {
    AStarPoint parent;
    float f, g, h;
    int in_closed_set;
} AStarNodeInfo;

int astar_is_valid(int x, int y) {
    return (x >= 0) && (x < ASTAR_GRID_WIDTH) && (y >= 0) && (y < ASTAR_GRID_HEIGHT);
}

int astar_is_unblocked(AStarMap* map, int x, int y) {
    return map->grid[y][x] == 0;
}

int astar_is_destination(int x, int y, AStarPoint dest) {
    return (x == dest.x && y == dest.y);
}

float astar_calculate_heuristic(int x, int y, AStarPoint dest) {
    // Manhattan distance
    return (float)abs(x - dest.x) + (float)abs(y - dest.y);
}

AStarPoint* astar_reconstruct_path(AStarNodeInfo node_details[][ASTAR_GRID_WIDTH], AStarPoint dest, int* path_len) {
    int x = dest.x;
    int y = dest.y;
    
    int len = 0;
    AStarNodeInfo temp_path[ASTAR_GRID_WIDTH * ASTAR_GRID_HEIGHT];
    
    while (!(node_details[y][x].parent.x == x && node_details[y][x].parent.y == y)) {
        temp_path[len++] = node_details[y][x];
        int temp_x = node_details[y][x].parent.x;
        int temp_y = node_details[y][x].parent.y;
        x = temp_x;
        y = temp_y;
    }
    
    // Add start node
    temp_path[len++] = node_details[y][x];
    
    // Allocate final path and reverse
    AStarPoint* path = (AStarPoint*)custom_malloc(len * sizeof(AStarPoint));
    if (!path) {
        *path_len = 0;
        return NULL;
    }
    
    for (int i = 0; i < len; i++) {
        path[i] = temp_path[len - 1 - i].parent;
    }
    *path_len = len;
    return path;
}

AStarPoint* a_star_search(AStarMap* map, AStarPoint start, AStarPoint dest, int* path_len) {
    *path_len = 0;
    if (!astar_is_valid(start.x, start.y) || !astar_is_valid(dest.x, dest.y)) return NULL;
    if (!astar_is_unblocked(map, start.x, start.y) || !astar_is_unblocked(map, dest.x, dest.y)) return NULL;
    
    // Node details grid
    AStarNodeInfo node_details[ASTAR_GRID_HEIGHT][ASTAR_GRID_WIDTH];
    
    // Initialize
    for (int y = 0; y < ASTAR_GRID_HEIGHT; y++) {
        for (int x = 0; x < ASTAR_GRID_WIDTH; x++) {
            node_details[y][x].f = FLT_MAX;
            node_details[y][x].g = FLT_MAX;
            node_details[y][x].h = FLT_MAX;
            node_details[y][x].parent = (AStarPoint){-1, -1};
            node_details[y][x].in_closed_set = 0;
        }
    }
    
    // Start node
    node_details[start.y][start.x].g = 0.0f;
    node_details[start.y][start.x].h = astar_calculate_heuristic(start.x, start.y, dest);
    node_details[start.y][start.x].f = node_details[start.y][start.x].h;
    node_details[start.y][start.x].parent = start;
    
    // Open list (priority queue)
    MinHeapAStar* open_list = min_heap_astar_create(ASTAR_GRID_WIDTH * ASTAR_GRID_HEIGHT);
    min_heap_astar_insert(open_list, start.x, start.y, node_details[start.y][start.x].f);
    
    AStarPoint* path = NULL;
    
    while (!min_heap_astar_is_empty(open_list)) {
        MinHeapAStarNode current = min_heap_astar_extract_min(open_list);
        int x = current.x;
        int y = current.y;
        
        node_details[y][x].in_closed_set = 1;
        
        if (astar_is_destination(x, y, dest)) {
            // Path found
            path = astar_reconstruct_path(node_details, dest, path_len);
            break;
        }
        
        // Check 4 neighbors
        int dx[] = {0, 0, 1, -1};
        int dy[] = {1, -1, 0, 0};
        
        for (int i = 0; i < 4; i++) {
            int nx = x + dx[i];
            int ny = y + dy[i];
            
            if (astar_is_valid(nx, ny) && astar_is_unblocked(map, nx, ny)) {
                if (node_details[ny][nx].in_closed_set) {
                    continue; // Already processed
                }
                
                float g_new = node_details[y][x].g + 1.0f; // Cost is 1
                float h_new = astar_calculate_heuristic(nx, ny, dest);
                float f_new = g_new + h_new;
                
                if (node_details[ny][nx].f == FLT_MAX || f_new < node_details[ny][nx].f) {
                    // Update details
                    node_details[ny][nx].g = g_new;
                    node_details[ny][nx].h = h_new;
                    node_details[ny][nx].f = f_new;
                    node_details[ny][nx].parent = (AStarPoint){x, y};
                    
                    if (!min_heap_astar_is_in_heap(open_list, nx, ny)) {
                        min_heap_astar_insert(open_list, nx, ny, f_new);
                    } else {
                        min_heap_astar_decrease_key(open_list, nx, ny, f_new);
                    }
                }
            }
        }
    }
    
    min_heap_astar_destroy(open_list);
    return path;
}


// ============================================================================
// NEW MODULE: C-like Lexer / Tokenizer (String State Machine)
// ============================================================================

typedef enum {
    TOKEN_LPAREN, TOKEN_RPAREN,
    TOKEN_LBRACE, TOKEN_RBRACE,
    TOKEN_LBRACKET, TOKEN_RBRACKET,
    TOKEN_COMMA, TOKEN_DOT, TOKEN_MINUS, TOKEN_PLUS,
    TOKEN_SEMICOLON, TOKEN_SLASH, TOKEN_STAR, TOKEN_PERCENT,
    
    TOKEN_BANG, TOKEN_BANG_EQUAL,
    TOKEN_EQUAL, TOKEN_EQUAL_EQUAL,
    TOKEN_GREATER, TOKEN_GREATER_EQUAL,
    TOKEN_LESS, TOKEN_LESS_EQUAL,
    
    TOKEN_IDENTIFIER, TOKEN_STRING, TOKEN_NUMBER,
    
    // Keywords
    TOKEN_IF, TOKEN_ELSE, TOKEN_WHILE, TOKEN_FOR,
    TOKEN_INT, TOKEN_CHAR, TOKEN_VOID, TOKEN_RETURN,
    TOKEN_STRUCT, TOKEN_TYPEDEF,
    
    TOKEN_ERROR, TOKEN_EOF
} TokenType;

typedef struct {
    TokenType type;
    const char* start;
    int length;
    int line;
} Token;

typedef struct {
    const char* start;
    const char* current;
    int line;
} Lexer;

static Lexer g_lexer;

void lexer_init(const char* source) {
    g_lexer.start = source;
    g_lexer.current = source;
    g_lexer.line = 1;
}

static int lexer_is_at_end() {
    return *g_lexer.current == '\0';
}

static char lexer_advance() {
    g_lexer.current++;
    return g_lexer.current[-1];
}

static char lexer_peek() {
    return *g_lexer.current;
}

static char lexer_peek_next() {
    if (lexer_is_at_end()) return '\0';
    return g_lexer.current[1];
}

static int lexer_match(char expected) {
    if (lexer_is_at_end()) return 0;
    if (*g_lexer.current != expected) return 0;
    g_lexer.current++;
    return 1;
}

static Token lexer_make_token(TokenType type) {
    Token token;
    token.type = type;
    token.start = g_lexer.start;
    token.length = (int)(g_lexer.current - g_lexer.start);
    token.line = g_lexer.line;
    return token;
}

static Token lexer_error_token(const char* message) {
    Token token;
    token.type = TOKEN_ERROR;
    token.start = message;
    token.length = (int)strlen(message);
    token.line = g_lexer.line;
    return token;
}

static int lexer_is_alpha(char c) {
    return (c >= 'a' && c <= 'z') ||
           (c >= 'A' && c <= 'Z') ||
            c == '_';
}

static int lexer_is_digit(char c) {
    return c >= '0' && c <= '9';
}

static void lexer_skip_whitespace_and_comments() {
    for (;;) {
        char c = lexer_peek();
        switch (c) {
            case ' ':
            case '\r':
            case '\t':
                lexer_advance();
                break;
            case '\n':
                g_lexer.line++;
                lexer_advance();
                break;
            case '/':
                if (lexer_peek_next() == '/') {
                    // Single-line comment
                    while (lexer_peek() != '\n' && !lexer_is_at_end()) {
                        lexer_advance();
                    }
                } else if (lexer_peek_next() == '*') {
                    // Block comment
                    lexer_advance(); // Consume /
                    lexer_advance(); // Consume *
                    while (!(lexer_peek() == '*' && lexer_peek_next() == '/') && !lexer_is_at_end()) {
                        if (lexer_peek() == '\n') g_lexer.line++;
                        lexer_advance();
                    }
                    if (!lexer_is_at_end()) lexer_advance(); // Consume *
                    if (!lexer_is_at_end()) lexer_advance(); // Consume /
                } else {
                    return; // It's just a slash operator
                }
                break;
            default:
                return;
        }
    }
}

static Token lexer_scan_string() {
    while (lexer_peek() != '"' && !lexer_is_at_end()) {
        if (lexer_peek() == '\n') g_lexer.line++;
        lexer_advance();
    }
    
    if (lexer_is_at_end()) return lexer_error_token("Unterminated string.");
    
    lexer_advance(); // Consume closing quote
    return lexer_make_token(TOKEN_STRING);
}

static Token lexer_scan_number() {
    while (lexer_is_digit(lexer_peek())) lexer_advance();
    
    if (lexer_peek() == '.' && lexer_is_digit(lexer_peek_next())) {
        lexer_advance(); // Consume '.'
        while (lexer_is_digit(lexer_peek())) lexer_advance();
    }
    
    return lexer_make_token(TOKEN_NUMBER);
}

static TokenType lexer_check_keyword(int start, int length, const char* rest, TokenType type) {
    if (g_lexer.current - g_lexer.start == start + length &&
        memcmp(g_lexer.start + start, rest, length) == 0) {
        return type;
    }
    return TOKEN_IDENTIFIER;
}

static TokenType lexer_identifier_type() {
    // Simple trie-like check for keywords
    switch (g_lexer.start[0]) {
        case 'c': 
            if (g_lexer.current - g_lexer.start > 1) {
                if (g_lexer.start[1] == 'h') return lexer_check_keyword(2, 2, "ar", TOKEN_CHAR);
            }
            break;
        case 'e': return lexer_check_keyword(1, 3, "lse", TOKEN_ELSE);
        case 'f': return lexer_check_keyword(1, 2, "or", TOKEN_FOR);
        case 'i': 
             if (g_lexer.current - g_lexer.start > 1) {
                if (g_lexer.start[1] == 'f') return lexer_check_keyword(1, 1, "f", TOKEN_IF);
                if (g_lexer.start[1] == 'n') return lexer_check_keyword(1, 2, "nt", TOKEN_INT);
            }
            break;
        case 'r': return lexer_check_keyword(1, 5, "eturn", TOKEN_RETURN);
        case 's': return lexer_check_keyword(1, 5, "truct", TOKEN_STRUCT);
        case 't': return lexer_check_keyword(1, 6, "ypedef", TOKEN_TYPEDEF);
        case 'v': return lexer_check_keyword(1, 3, "oid", TOKEN_VOID);
        case 'w': return lexer_check_keyword(1, 4, "hile", TOKEN_WHILE);
    }
    return TOKEN_IDENTIFIER;
}

static Token lexer_scan_identifier() {
    while (lexer_is_alpha(lexer_peek()) || lexer_is_digit(lexer_peek())) {
        lexer_advance();
    }
    return lexer_make_token(lexer_identifier_type());
}

Token lexer_scan_token() {
    lexer_skip_whitespace_and_comments();
    
    g_lexer.start = g_lexer.current;
    
    if (lexer_is_at_end()) return lexer_make_token(TOKEN_EOF);
    
    char c = lexer_advance();
    
    if (lexer_is_alpha(c)) return lexer_scan_identifier();
    if (lexer_is_digit(c)) return lexer_scan_number();
    
    switch (c) {
        case '(': return lexer_make_token(TOKEN_LPAREN);
        case ')': return lexer_make_token(TOKEN_RPAREN);
        case '{': return lexer_make_token(TOKEN_LBRACE);
        case '}': return lexer_make_token(TOKEN_RBRACE);
        case '[': return lexer_make_token(TOKEN_LBRACKET);
        case ']': return lexer_make_token(TOKEN_RBRACKET);
        case ';': return lexer_make_token(TOKEN_SEMICOLON);
        case ',': return lexer_make_token(TOKEN_COMMA);
        case '.': return lexer_make_token(TOKEN_DOT);
        case '-': return lexer_make_token(TOKEN_MINUS);
        case '+': return lexer_make_token(TOKEN_PLUS);
        case '*': return lexer_make_token(TOKEN_STAR);
        case '%': return lexer_make_token(TOKEN_PERCENT);
        
        case '!': return lexer_make_token(lexer_match('=') ? TOKEN_BANG_EQUAL : TOKEN_BANG);
        case '=': return lexer_make_token(lexer_match('=') ? TOKEN_EQUAL_EQUAL : TOKEN_EQUAL);
        case '<': return lexer_make_token(lexer_match('=') ? TOKEN_LESS_EQUAL : TOKEN_LESS);
        case '>': return lexer_make_token(lexer_match('=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER);
        
        case '/': return lexer_make_token(TOKEN_SLASH); // Comments handled in skip
        
        case '"': return lexer_scan_string();
    }
    
    return lexer_error_token("Unexpected character.");
}


// ============================================================================
// Main Test Suite (Original)
// ============================================================================

void run_math_tests() {
    printf("\n=== Mathematical Operations Tests ===\n");
    
    // Fibonacci
    printf("Fibonacci(10) = %d\n", fibonacci(10));
    printf("Fibonacci(15) = %d\n", fibonacci(15));
    
    // Prime checking
    int primes_found = 0;
    for (int i = 2; i < 100; i++) {
        if (is_prime(i)) {
            primes_found++;
        }
    }
    printf("Primes found (2-100): %d\n", primes_found);
    
    // Power mod
    printf("2^10 mod 1000 = %lld\n", power_mod(2, 10, 1000));
    printf("7^100 mod 13 = %lld\n", power_mod(7, 100, 13));
}

void run_array_tests() {
    printf("\n=== Array Operations Tests ===\n");
    
    int arr[] = {64, 34, 25, 12, 22, 11, 90, 88, 45, 50, 23, 36, 18, 77, 55};
    int n = sizeof(arr) / sizeof(arr[0]);
    
    printf("Original array: ");
    for (int i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");
    
    bubble_sort(arr, n);
    
    printf("Sorted array: ");
    for (int i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");
    
    int target = 45;
    int pos = binary_search(arr, n, target);
    printf("Binary search for %d: found at index %d\n", target, pos);
    
    rotate_array(arr, n, 3);
    printf("After rotation: ");
    for (int i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");
}

void run_linked_list_tests() {
    printf("\n=== Linked List Tests ===\n");
    
    Node* head = NULL;
    for (int i = 10; i > 0; i--) {
        head = insert_head(head, i * 10);
    }
    
    printf("List created with 10 nodes\n");
    printf("Has cycle: %s\n", has_cycle(head) ? "Yes" : "No");
    
    head = reverse_list(head);
    printf("List reversed\n");
    
    // Create second list for merging
    Node* head2 = NULL;
    for (int i = 5; i > 0; i--) {
        head2 = insert_head(head2, i * 15);
    }
    
    Node* merged = merge_sorted_lists(head, head2);
    printf("Two sorted lists merged\n");
}

void run_graph_tests() {
    printf("\n=== Graph Tests ===\n");
    
    Graph* g = create_graph(6);
    
    add_edge(g,  0, 1);
    add_edge(g, 0, 2);
    add_edge(g, 1, 3);
    add_edge(g, 2, 3);
    add_edge(g, 3, 4);
    add_edge(g, 4, 5);
    
    printf("Graph created with %d vertices and %d edges\n", g->vertices, g->edges);
    printf("Graph is connected: %s\n", is_connected(g) ? "Yes" : "No");
}

void run_banking_tests() {
    printf("\n=== Banking System Tests ===\n");
    
    BankingSystem* bank = init_banking_system(10);
    
    create_account(bank, 0, "Alice", 1000.0);
    create_account(bank, 1, "Bob", 2000.0);
    create_account(bank, 2, "Charlie", 1500.0);
    create_account(bank, 3, "David", 3000.0);
    create_account(bank, 4, "Eve", 2500.0);
    
    printf("Created 5 accounts\n");
    printf("Total assets: $%.2f\n", get_total_assets(bank));
    
    transfer(bank, 0, 1, 500.0);
    transfer(bank, 3, 2, 1000.0);
    transfer(bank, 4, 0, 750.0);
    
    printf("After 3 transfers\n");
    printf("Total assets: $%.2f\n", get_total_assets(bank));
    printf("Errors encountered: %d\n", bank->error_count);
}

void run_crypto_tests() {
    printf("\n=== Cryptographic Tests ===\n");
    
    char text1[] = "HelloWorld";
    printf("Hash of '%s': %lu\n", text1, hash_string(text1));
    
    char text2[] = "The quick brown fox jumps over the lazy dog";
    printf("Original: %s\n", text2);
    
    caesar_encrypt(text2, 13);
    printf("Caesar(13): %s\n", text2);
    
    caesar_encrypt(text2, 13);  // Decrypt
    printf("Decrypted: %s\n", text2);
    
    char key[] = "SECRET";
    xor_encrypt(text2, strlen(text2), key, strlen(key));
    printf("XOR encrypted (binary)\n");
    xor_encrypt(text2, strlen(text2), key, strlen(key));  // Decrypt
    printf("XOR decrypted: %s\n", text2);
}

void run_function_pointer_tests() {
    printf("\n=== Function Pointer Tests ===\n");
    
    printf("10 + 5 = %d\n", calculator(10, 5, 0));
    printf("10 - 5 = %d\n", calculator(10, 5, 1));
    printf("10 * 5 = %d\n", calculator(10, 5, 2));
    printf("10 / 5 = %d\n", calculator(10, 5, 3));
    
    MathOperation op = multiply;
    printf("Using function pointer: 7 * 8 = %d\n", apply_operation(7, 8, op));
}

void run_string_tests() {
    printf("\n=== String Processing Tests ===\n");
    
    char str[] = "Fault Injection Hardening";
    printf("Original: %s\n", str);
    
    reverse_string(str);
    printf("Reversed: %s\n", str);
    
    reverse_string(str);  // Reverse back
    printf("Restored: %s\n", str);
    
    const char* text = "ABABDABACDABABCABAB";
    const char* pattern = "ABABCABAB";
    int pos = kmp_search(text, pattern);
    printf("Pattern '%s' found at position: %d\n", pattern, pos);
}

// ============================================================================
// NEW MODULE: Test Suites
// ============================================================================

void run_btree_tests() {
    printf("\n=== B-Tree Tests ===\n");
    
    BTree* tree = btree_create();
    
    int keys_to_insert[] = {10, 20, 5, 6, 12, 30, 7, 17, 3, 1, 40, 50, 25, 35};
    int n = sizeof(keys_to_insert) / sizeof(keys_to_insert[0]);
    
    printf("Inserting %d keys...\n", n);
    for (int i = 0; i < n; i++) {
        btree_insert(tree, keys_to_insert[i]);
    }
    
    printf("B-Tree traversal (in-order):");
    btree_traverse(tree->root);
    printf("\n");
    
    int key_to_find = 30;
    BTreeNode* result = btree_search(tree->root, key_to_find);
    printf("Search for %d: %s\n", key_to_find, result ? "Found" : "Not Found");
    
    key_to_find = 99;
    result = btree_search(tree->root, key_to_find);
    printf("Search for %d: %s\n", key_to_find, result ? "Found" : "Not Found");
    
    int keys_to_delete[] = {6, 17, 10, 50};
    n = sizeof(keys_to_delete) / sizeof(keys_to_delete[0]);
    
    printf("Deleting %d keys...\n", n);
    for (int i = 0; i < n; i++) {
        btree_delete_key(tree, keys_to_delete[i]);
    }

    printf("B-Tree traversal after deletes:");
    btree_traverse(tree->root);
    printf("\n");

    btree_destroy(tree->root);
    free(tree);
    printf("B-Tree destroyed.\n");
}

void run_allocator_tests() {
    printf("\n=== Custom Allocator Tests ===\n");
    
    // Init is called by first malloc
    
    printf("Allocating 10 blocks of 1KB...\n");
    void* ptrs[10];
    for (int i = 0; i < 10; i++) {
        ptrs[i] = custom_malloc(1024);
        if (ptrs[i]) {
            // Write some data
            memset(ptrs[i], i, 1024);
        }
    }
    
    size_t total_free, total_used;
    int free_blocks;
    heap_get_stats(&total_free, &total_used, &free_blocks);
    printf("Stats after 10 allocs: Used: %zu, Free: %zu, Free Blocks: %d\n", total_used, total_free, free_blocks);

    printf("Freeing even-numbered blocks (0, 2, 4, 6, 8)...\n");
    for (int i = 0; i < 10; i += 2) {
        custom_free(ptrs[i]);
        ptrs[i] = NULL;
    }
    
    heap_get_stats(&total_free, &total_used, &free_blocks);
    printf("Stats after 5 frees: Used: %zu, Free: %zu, Free Blocks: %d\n", total_used, total_free, free_blocks);

    printf("Allocating one large 4KB block (should use coalesced space)...\n");
    void* large_ptr = custom_malloc(4096);
    if(large_ptr) {
        printf("Large alloc successful.\n");
    } else {
        printf("Large alloc failed.\n");
    }

    heap_get_stats(&total_free, &total_used, &free_blocks);
    printf("Stats after large alloc: Used: %zu, Free: %zu, Free Blocks: %d\n", total_used, total_free, free_blocks);

    printf("Reallocating large block to 8KB...\n");
    void* larger_ptr = custom_realloc(large_ptr, 8192);
    if(larger_ptr) {
        printf("Realloc to 8KB successful.\n");
    }

    printf("Freeing all remaining blocks...\n");
    for (int i = 0; i < 10; i++) {
        if (ptrs[i]) custom_free(ptrs[i]);
    }
    custom_free(larger_ptr);
    
    heap_get_stats(&total_free, &total_used, &free_blocks);
    printf("Stats after final free: Used: %zu, Free: %zu, Free Blocks: %d\n", total_used, total_free, free_blocks);
}

void run_vm_tests() {
    printf("\n=== Virtual Machine Tests ===\n");
    
    // Program: Factorial of 5 (recursive)
    // 
    // ; --- main ---
    // 0: PUSH 5
    // 2: CALL 8
    // 4: PRINT
    // 5: HALT
    // 
    // ; --- factorial(n) ---
    // 8: STORE 0      ; store n in mem[0]
    // 10: LOAD 0
    // 12: PUSH 1
    // 14: CMP
    // 15: JG 20      ; if (n > 1)
    // 
    // ; base case (n <= 1)
    // 17: PUSH 1
    // 19: RET
    // 
    // ; recursive case (n > 1)
    // 20: LOAD 0      ; push n
    // 22: LOAD 0      ; push n
    // 24: PUSH 1
    // 26: SUB         ; n-1
    // 27: CALL 8      ; fact(n-1)
    // 29: MUL         ; n * fact(n-1)
    // 30: RET
    
    int32_t factorial_program[] = {
        OP_PUSH, 5,   // 0
        OP_CALL, 8,   // 2
        OP_PRINT,     // 4
        OP_HALT,      // 5
        OP_NOP, OP_NOP, // 6, 7
        // --- factorial (addr 8) ---
        OP_STORE, 0,  // 8
        OP_LOAD, 0,   // 10
        OP_PUSH, 1,   // 12
        OP_CMP,       // 14
        OP_JG, 20,    // 15
        // base case
        OP_PUSH, 1,   // 17
        OP_RET,       // 19
        // recursive case
        OP_LOAD, 0,   // 20
        OP_LOAD, 0,   // 22
        OP_PUSH, 1,   // 24
        OP_SUB,       // 26
        OP_CALL, 8,   // 27
        OP_MUL,       // 29
        OP_RET        // 30
    };
    int program_size = sizeof(factorial_program) / sizeof(factorial_program[0]);
    
    VM* vm = vm_create();
    if (!vm) {
        printf("Failed to create VM (likely custom_malloc failed).\n");
        return;
    }
    
    printf("Loading factorial program (%d instructions)...\n", program_size);
    vm_load_program(vm, factorial_program, program_size);
    
    printf("Running VM...\n");
    vm_run(vm);
    printf("VM Halted.\n");
    
    vm_destroy(vm);
}

void run_astar_tests() {
    printf("\n=== A* Pathfinding Tests ===\n");
    
    AStarMap* map = (AStarMap*)custom_malloc(sizeof(AStarMap));
    memset(map, 0, sizeof(AStarMap)); // All walkable
    
    // Create a wall
    for (int i = 2; i < 15; i++) {
        map->grid[i][10] = 1; // obstacle
    }
    
    AStarPoint start = {1, 5};
    AStarPoint dest = {18, 5};
    
    printf("Finding path from (%d, %d) to (%d, %d)\n", start.x, start.y, dest.x, dest.y);
    
    int path_len = 0;
    AStarPoint* path = a_star_search(map, start, dest, &path_len);
    
    if (path) {
        printf("Path found! Length: %d steps.\n", path_len);
        printf("Path: ");
        for (int i = 0; i < path_len; i++) {
            printf("(%d,%d) ", path[i].x, path[i].y);
        }
        printf("\n");
        custom_free(path);
    } else {
        printf("No path found.\n");
    }
    
    custom_free(map);
}

void run_lexer_tests() {
    printf("\n=== C-like Lexer Tests ===\n");
    
    const char* source_code = 
        "/* Test Program */\n"
        "int main() {\n"
        "  int x = 10 + 20 * 30;\n"
        "  if (x >= 900) {\n"
        "    char* s = \"Hello World!\\n\";\n"
        "  }\n"
        "  // End of test\n"
        "  return 0;\n"
        "}\n";
        
    printf("Tokenizing sample code:\n---\n%s---\n", source_code);
    
    lexer_init(source_code);
    
    int line = -1;
    int token_count = 0;
    for (;;) {
        Token token = lexer_scan_token();
        if (token.line != line) {
            printf("\nLine %d: ", token.line);
            line = token.line;
        }
        
        printf("[Type %d, '%.*s'] ", token.type, token.length, token.start);
        token_count++;
        
        if (token.type == TOKEN_EOF || token.type == TOKEN_ERROR) {
            if (token.type == TOKEN_ERROR) {
                 printf("\nLexer Error: %.*s\n", token.length, token.start);
            }
            break;
        }
    }
    printf("\n---\nTotal tokens: %d\n", token_count);
}


// ============================================================================
// Main Function (Updated)
// ============================================================================

int main() {
    printf("========================================\n");
    printf("Comprehensive FI Hardening Test Suite\n");
    printf("========================================\n");
    
    // --- Original Tests ---
    run_math_tests();
    run_array_tests();
    run_linked_list_tests();
    run_graph_tests();
    run_banking_tests();
    run_crypto_tests();
    run_function_pointer_tests();
    run_string_tests();
    
    // --- New Module Tests ---
    // Note: These tests use the custom allocator, so it's tested implicitly
    // before its explicit test function.
    
    run_btree_tests();
    run_vm_tests();
    run_astar_tests();
    run_lexer_tests();
    
    // Explicitly test the allocator's robustness
    run_allocator_tests();
    
    printf("\n========================================\n");
    printf("All Tests Completed Successfully!\n");
    printf("========================================\n");
    
    return 0;
}