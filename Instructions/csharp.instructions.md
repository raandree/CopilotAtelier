---
applyTo: "**/*.cs,**/*.csx"
---

# C# Best Practices and Standards

## Naming Conventions

### PascalCase
- **Classes and Structs**: `public class CustomerAccount { }`
- **Interfaces**: Prefix with 'I': `public interface ICustomerRepository { }`
- **Methods**: `public void ProcessPayment() { }`
- **Properties**: `public string CustomerName { get; set; }`
- **Events**: `public event EventHandler DataLoaded;`
- **Namespaces**: `namespace MyCompany.ProductName.Feature`
- **Enums and Enum Values**: `public enum OrderStatus { Pending, Shipped }`
- **Public Fields**: `public const int MaxRetries = 3;` (avoid public fields when possible)

### camelCase
- **Private Fields**: Prefix with underscore: `private readonly ILogger _logger;`
- **Local Variables**: `var customerCount = 10;`
- **Method Parameters**: `public void AddCustomer(string customerName, int age)`

### ALL_CAPS
- **Constants**: `private const int MAX_BUFFER_SIZE = 1024;`

### Naming Examples
```csharp
// Good
public class CustomerRepository : ICustomerRepository
{
    private readonly ILogger _logger;
    private const int MAX_RETRY_COUNT = 3;
    
    public string CustomerName { get; set; }
    
    public async Task<Customer> GetCustomerAsync(int customerId)
    {
        var customer = await _database.FindAsync(customerId);
        return customer;
    }
}

// Avoid
public class customerrepository  // Wrong casing
{
    public string custName;  // Avoid public fields, use properties
    
    public Customer getCustomer(int id)  // Wrong method naming
    {
        Customer c = FindCustomer(id);  // Non-descriptive variable name
        return c;
    }
}
```

## Code Style and Formatting

### Indentation and Braces (Allman Style)
- Use 4 spaces for indentation (NOT tabs)
- Opening brace on new line
- Closing brace on its own line, aligned with statement

```csharp
// Correct - Allman style (Microsoft standard)
public class ExampleClass
{
    public void ExampleMethod()
    {
        if (condition)
        {
            DoSomething();
        }
        else
        {
            DoSomethingElse();
        }
    }
}

// Incorrect - K&R style (not C# standard)
public class ExampleClass {
    public void ExampleMethod() {
        if (condition) {
            DoSomething();
        }
    }
}
```

### Line Length and Breaks
- Keep lines under 65-80 characters when possible (especially for documentation)
- Break long lines at logical points
- Line breaks should occur before binary operators

```csharp
// Good - readable line breaks
var result = longVariableName 
    + anotherLongVariableName 
    + thirdLongVariableName;

// Method call with many parameters
var customer = _repository.CreateCustomer(
    firstName: "John",
    lastName: "Doe",
    email: "john.doe@example.com",
    phoneNumber: "555-0100"
);
```

### Whitespace
```csharp
// Spaces after commas
var numbers = new[] { 1, 2, 3, 4, 5 };

// Spaces around operators
var result = value1 + value2;
var condition = (x == 5) && (y > 10);

// No spaces inside parentheses
if (condition) { }  // Correct
if ( condition ) { }  // Incorrect

// One space after control keywords
if (condition)
while (isRunning)
for (int i = 0; i < count; i++)
```

## Type Usage

### Language Keywords vs. Runtime Types
Always use language keywords instead of runtime types:

```csharp
// Correct - use language keywords
string name = "John";
int age = 30;
bool isActive = true;
object data = GetData();

// Incorrect - using runtime types
String name = "John";  // Don't use System.String
Int32 age = 30;        // Don't use System.Int32
Boolean isActive = true;  // Don't use System.Boolean
Object data = GetData();  // Don't use System.Object
```

### Implicit vs. Explicit Typing

**Use `var` when:**
- Type is obvious from the right side of assignment
- With `new` operator
- With explicit casts
- With literal values

```csharp
// Good - type is obvious
var message = "This is clearly a string";
var customer = new Customer();
var count = 5;
var items = new List<string>();
```

**Use explicit types when:**
- Type is not obvious from the expression
- Readability is improved
- Working with numeric types to avoid confusion

```csharp
// Good - explicit types for clarity
IEnumerable<Customer> customers = GetCustomers();
int maxRetries = CalculateMaxRetries();
string userName = Console.ReadLine();  // Not obvious from ReadLine()
```

**Avoid `var` for:**
- Loop variables in `foreach` (use explicit type)
- When type name provides important semantic information

```csharp
// Correct - explicit type in foreach
foreach (Customer customer in customers)
{
    Console.WriteLine(customer.Name);
}

// Avoid - not clear what we're iterating
foreach (var item in customers)
{
    Console.WriteLine(item.Name);
}
```

## Modern C# Features (Use When Appropriate)

### Nullable Reference Types (C# 8.0+)
Enable nullable reference types in your project:

```csharp
// Enable in .csproj
<Nullable>enable</Nullable>

// Use nullable annotations
public class Customer
{
    public string Name { get; set; } = string.Empty;  // Non-nullable
    public string? MiddleName { get; set; }           // Nullable
    
    public void ProcessCustomer(Customer? customer)
    {
        if (customer is null)
        {
            throw new ArgumentNullException(nameof(customer));
        }
        
        // Use null-forgiving operator only when certain
        var name = customer.Name;
    }
}
```

### Pattern Matching (C# 7.0+)
```csharp
// Type pattern
if (obj is Customer customer)
{
    Console.WriteLine(customer.Name);
}

// Switch expression (C# 8.0+)
var discount = customerType switch
{
    CustomerType.Premium => 0.20m,
    CustomerType.Regular => 0.10m,
    CustomerType.New => 0.05m,
    _ => 0.0m
};

// Property pattern (C# 8.0+)
if (customer is { IsActive: true, Age: >= 18 })
{
    ProcessAdultCustomer(customer);
}
```

### Records (C# 9.0+)
Use for immutable data transfer objects:

```csharp
// Record with positional syntax
public record CustomerDto(int Id, string Name, string Email);

// Record with property syntax
public record Customer
{
    public int Id { get; init; }
    public required string Name { get; init; }
    public string? Email { get; init; }
}
```

### Primary Constructors (C# 12.0+)
```csharp
// Class with primary constructor
public class CustomerService(ILogger logger, ICustomerRepository repository)
{
    private readonly ILogger _logger = logger;
    private readonly ICustomerRepository _repository = repository;
    
    public async Task<Customer> GetCustomerAsync(int id)
    {
        _logger.LogInformation("Retrieving customer {CustomerId}", id);
        return await _repository.GetByIdAsync(id);
    }
}
```

### Collection Expressions (C# 12.0+)
```csharp
// Array initialization
int[] numbers = [1, 2, 3, 4, 5];

// List initialization
List<string> names = ["Alice", "Bob", "Charlie"];

// Spread operator
int[] moreNumbers = [..numbers, 6, 7, 8];
```

## String Handling

### String Interpolation (Preferred)
```csharp
// Good - string interpolation
var message = $"Hello, {customer.Name}! Your order #{order.Id} is ready.";

// Good - multi-line interpolation
var html = $@"
    <div>
        <h1>{customer.Name}</h1>
        <p>Email: {customer.Email}</p>
    </div>";
```

### Raw String Literals (C# 11.0+)
```csharp
// Raw string literal - no escape sequences needed
var json = """
    {
        "name": "John Doe",
        "email": "john@example.com",
        "address": "123 Main St\nApt 4"
    }
    """;
```

### StringBuilder for Loops
```csharp
// Good - use StringBuilder for concatenation in loops
var builder = new StringBuilder();
for (int i = 0; i < 10000; i++)
{
    builder.AppendLine($"Line {i}");
}
var result = builder.ToString();

// Avoid - poor performance
var result = string.Empty;
for (int i = 0; i < 10000; i++)
{
    result += $"Line {i}\n";  // Creates new string each iteration
}
```

## Exception Handling

### Try-Catch-Finally
```csharp
// Good - specific exception types
try
{
    var data = await _repository.GetDataAsync(id);
    return ProcessData(data);
}
catch (EntityNotFoundException ex)
{
    _logger.LogWarning(ex, "Entity not found: {EntityId}", id);
    throw;
}
catch (DatabaseException ex)
{
    _logger.LogError(ex, "Database error occurred");
    throw new ApplicationException("Unable to retrieve data", ex);
}
finally
{
    // Cleanup code
    CleanupResources();
}
```

### Throwing Exceptions
```csharp
// Good - use appropriate exception types
public void ProcessOrder(Order order)
{
    if (order is null)
    {
        throw new ArgumentNullException(nameof(order));
    }
    
    if (order.Items.Count == 0)
    {
        throw new InvalidOperationException("Order must contain at least one item");
    }
    
    if (order.Total < 0)
    {
        throw new ArgumentOutOfRangeException(nameof(order.Total), 
            "Order total cannot be negative");
    }
}
```

### Using Statements for Resource Management
```csharp
// Good - using statement (preferred)
using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();
// Connection automatically disposed at end of scope

// Traditional using block (when scope control needed)
using (var stream = File.OpenRead(filePath))
{
    // Process stream
}  // Stream disposed here
```

### Exception Filters (C# 6.0+)
```csharp
// Use exception filters for conditional catch
try
{
    ProcessData();
}
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
{
    _logger.LogWarning("Resource not found");
    return NotFound();
}
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized)
{
    _logger.LogWarning("Unauthorized access");
    return Unauthorized();
}
```

## LINQ and Collections

### LINQ Query Syntax vs. Method Syntax
Use method syntax (more concise and flexible):

```csharp
// Preferred - method syntax
var activeCustomers = customers
    .Where(c => c.IsActive)
    .OrderBy(c => c.Name)
    .Select(c => new CustomerDto(c.Id, c.Name, c.Email))
    .ToList();

// Query syntax (use when more readable for complex queries)
var customerOrders = 
    from customer in customers
    join order in orders on customer.Id equals order.CustomerId
    where customer.IsActive
    select new { customer.Name, order.Total };
```

### Collection Initialization
```csharp
// Modern collection expressions (C# 12.0+)
List<int> numbers = [1, 2, 3, 4, 5];

// Traditional collection initializer
var customers = new List<Customer>
{
    new() { Id = 1, Name = "Alice" },
    new() { Id = 2, Name = "Bob" }
};

// Dictionary initialization
var statusCodes = new Dictionary<int, string>
{
    [200] = "OK",
    [404] = "Not Found",
    [500] = "Internal Server Error"
};
```

## Async/Await Best Practices

### Async Method Naming
Always suffix async methods with "Async":

```csharp
// Correct
public async Task<Customer> GetCustomerAsync(int id)
{
    return await _repository.FindAsync(id);
}

// Incorrect
public async Task<Customer> GetCustomer(int id)  // Missing Async suffix
{
    return await _repository.FindAsync(id);
}
```

### Avoid Async Void
```csharp
// NEVER use async void (except for event handlers)
// Bad
public async void ProcessData()  // Exceptions can't be caught!
{
    await DoSomethingAsync();
}

// Good - return Task
public async Task ProcessDataAsync()
{
    await DoSomethingAsync();
}

// Exception - event handlers must be async void
private async void Button_Click(object sender, EventArgs e)
{
    try
    {
        await ProcessDataAsync();
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error in event handler");
    }
}
```

### ConfigureAwait
```csharp
// In library code, use ConfigureAwait(false) to avoid deadlocks
public async Task<Data> GetDataAsync()
{
    var result = await _httpClient
        .GetAsync(url)
        .ConfigureAwait(false);
    
    return await result.Content
        .ReadAsAsync<Data>()
        .ConfigureAwait(false);
}

// In UI code (WPF, WinForms), omit ConfigureAwait to stay on UI thread
private async void LoadButton_Click(object sender, EventArgs e)
{
    var data = await GetDataAsync();  // Returns to UI thread
    DataGrid.ItemsSource = data;       // Can update UI safely
}
```

### Task Cancellation
```csharp
public async Task<Data> FetchDataAsync(CancellationToken cancellationToken = default)
{
    try
    {
        using var response = await _httpClient.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsAsync<Data>(cancellationToken);
    }
    catch (OperationCanceledException)
    {
        _logger.LogInformation("Operation was cancelled");
        throw;
    }
}
```

## Security Best Practices

### Input Validation (CRITICAL)
**ALWAYS validate and sanitize user input:**

```csharp
// Good - comprehensive validation
public class CustomerValidator
{
    public ValidationResult Validate(CustomerInput input)
    {
        var errors = new List<string>();
        
        // Null checks
        if (string.IsNullOrWhiteSpace(input.Name))
        {
            errors.Add("Name is required");
        }
        
        // Length validation
        if (input.Name?.Length > 100)
        {
            errors.Add("Name must not exceed 100 characters");
        }
        
        // Format validation
        if (!IsValidEmail(input.Email))
        {
            errors.Add("Invalid email format");
        }
        
        // Range validation
        if (input.Age < 0 || input.Age > 150)
        {
            errors.Add("Age must be between 0 and 150");
        }
        
        return new ValidationResult(errors);
    }
    
    private bool IsValidEmail(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
            return false;
            
        try
        {
            var addr = new System.Net.Mail.MailAddress(email);
            return addr.Address == email;
        }
        catch
        {
            return false;
        }
    }
}
```

### SQL Injection Prevention (CRITICAL)
**ALWAYS use parameterized queries:**

```csharp
// GOOD - Parameterized query (SAFE)
public async Task<Customer> GetCustomerAsync(int customerId)
{
    const string sql = "SELECT * FROM Customers WHERE CustomerId = @CustomerId";
    
    using var connection = new SqlConnection(_connectionString);
    using var command = new SqlCommand(sql, connection);
    
    // Use parameters - NEVER concatenate user input!
    command.Parameters.AddWithValue("@CustomerId", customerId);
    
    await connection.OpenAsync();
    using var reader = await command.ExecuteReaderAsync();
    
    return MapToCustomer(reader);
}

// BAD - SQL Injection vulnerability (NEVER DO THIS!)
public async Task<Customer> GetCustomerUnsafe(string customerName)
{
    // VULNERABLE - user input directly concatenated!
    string sql = $"SELECT * FROM Customers WHERE Name = '{customerName}'";
    // Attacker could input: '; DROP TABLE Customers; --
    
    using var connection = new SqlConnection(_connectionString);
    using var command = new SqlCommand(sql, connection);
    // ... DISASTER WAITING TO HAPPEN
}

// GOOD - Using Entity Framework (parameterized automatically)
public async Task<Customer> GetCustomerEFAsync(int customerId)
{
    return await _context.Customers
        .FirstOrDefaultAsync(c => c.Id == customerId);
}
```

### Cross-Site Scripting (XSS) Prevention
```csharp
// GOOD - Encode output in web applications
using System.Web;

public string GetSafeHtmlContent(string userInput)
{
    // Always encode user input before rendering
    return HttpUtility.HtmlEncode(userInput);
}

// In ASP.NET Core Razor, @ automatically encodes
@Model.UserInput  // Automatically HTML encoded

// For JavaScript context, use JSON encoding
<script>
    var userName = @Html.Raw(Json.Serialize(Model.UserName));
</script>
```

### Secure Password Handling
```csharp
// GOOD - Use secure hashing with salt
using System.Security.Cryptography;

public class PasswordHasher
{
    private const int SaltSize = 16;
    private const int HashSize = 32;
    private const int Iterations = 100000;
    
    public string HashPassword(string password)
    {
        // Generate salt
        byte[] salt = RandomNumberGenerator.GetBytes(SaltSize);
        
        // Generate hash
        var pbkdf2 = new Rfc2898DeriveBytes(
            password, 
            salt, 
            Iterations, 
            HashAlgorithmName.SHA256
        );
        byte[] hash = pbkdf2.GetBytes(HashSize);
        
        // Combine salt and hash
        byte[] hashBytes = new byte[SaltSize + HashSize];
        Array.Copy(salt, 0, hashBytes, 0, SaltSize);
        Array.Copy(hash, 0, hashBytes, SaltSize, HashSize);
        
        return Convert.ToBase64String(hashBytes);
    }
    
    public bool VerifyPassword(string password, string hashedPassword)
    {
        byte[] hashBytes = Convert.FromBase64String(hashedPassword);
        
        // Extract salt
        byte[] salt = new byte[SaltSize];
        Array.Copy(hashBytes, 0, salt, 0, SaltSize);
        
        // Compute hash of provided password
        var pbkdf2 = new Rfc2898DeriveBytes(
            password, 
            salt, 
            Iterations, 
            HashAlgorithmName.SHA256
        );
        byte[] hash = pbkdf2.GetBytes(HashSize);
        
        // Compare hashes
        for (int i = 0; i < HashSize; i++)
        {
            if (hashBytes[i + SaltSize] != hash[i])
                return false;
        }
        
        return true;
    }
}

// NEVER store passwords in plain text!
// BAD
public class UserBad
{
    public string Password { get; set; }  // NEVER do this!
}
```

### Secure API Keys and Secrets
```csharp
// GOOD - Use configuration and secret management
public class ApiService
{
    private readonly string _apiKey;
    
    public ApiService(IConfiguration configuration)
    {
        // Store secrets in:
        // - appsettings.json (development, not checked into source control)
        // - Azure Key Vault (production)
        // - Environment variables
        // - User Secrets (development)
        _apiKey = configuration["ApiKeys:ThirdPartyService"] 
            ?? throw new InvalidOperationException("API key not configured");
    }
}

// BAD - Hardcoded secrets (NEVER do this!)
public class ApiServiceBad
{
    private const string API_KEY = "sk_live_abc123xyz";  // NEVER hardcode secrets!
}

// Use .NET User Secrets in development
// dotnet user-secrets init
// dotnet user-secrets set "ApiKeys:ThirdPartyService" "your-key-here"
```

### Avoid Deserialization Vulnerabilities
```csharp
// GOOD - Use safe deserialization with type restrictions
public class SafeDeserializer
{
    public T Deserialize<T>(string json) where T : class
    {
        var options = new JsonSerializerOptions
        {
            // Restrict to known types only
            TypeInfoResolver = new DefaultJsonTypeInfoResolver()
        };
        
        return JsonSerializer.Deserialize<T>(json, options)
            ?? throw new InvalidOperationException("Deserialization failed");
    }
}

// BAD - Unsafe deserialization
// Never use BinaryFormatter - it's insecure!
// [Obsolete("BinaryFormatter is obsolete and should not be used.")]
```

### Path Traversal Prevention
```csharp
// GOOD - Validate file paths
public string GetSafeFilePath(string userProvidedFileName)
{
    // Remove any path traversal attempts
    var fileName = Path.GetFileName(userProvidedFileName);
    
    // Validate file name
    if (string.IsNullOrWhiteSpace(fileName) || 
        fileName.Contains("..") ||
        Path.GetInvalidFileNameChars().Any(fileName.Contains))
    {
        throw new ArgumentException("Invalid file name", nameof(userProvidedFileName));
    }
    
    // Combine with safe base directory
    var safeBasePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "MyApp",
        "Uploads"
    );
    
    return Path.Combine(safeBasePath, fileName);
}

// BAD - Direct path concatenation
public string GetFilePathUnsafe(string userPath)
{
    // VULNERABLE - user could provide "../../../etc/passwd"
    return Path.Combine("uploads", userPath);
}
```

### Cross-Site Request Forgery (CSRF) Protection
```csharp
// In ASP.NET Core, use anti-forgery tokens
[HttpPost]
[ValidateAntiForgeryToken]  // Enforces CSRF protection
public async Task<IActionResult> ProcessPayment(PaymentModel model)
{
    if (!ModelState.IsValid)
    {
        return View(model);
    }
    
    await _paymentService.ProcessAsync(model);
    return RedirectToAction("Confirmation");
}

// In Razor views, include token
@using (Html.BeginForm("ProcessPayment", "Payment", FormMethod.Post))
{
    @Html.AntiForgeryToken()
    <!-- Form fields -->
}
```

## Dependency Injection

### Constructor Injection (Preferred)
```csharp
// Good - constructor injection with readonly fields
public class CustomerService
{
    private readonly ICustomerRepository _repository;
    private readonly ILogger<CustomerService> _logger;
    private readonly IMapper _mapper;
    
    public CustomerService(
        ICustomerRepository repository,
        ILogger<CustomerService> logger,
        IMapper mapper)
    {
        _repository = repository ?? throw new ArgumentNullException(nameof(repository));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _mapper = mapper ?? throw new ArgumentNullException(nameof(mapper));
    }
    
    public async Task<CustomerDto> GetCustomerAsync(int id)
    {
        _logger.LogInformation("Retrieving customer {CustomerId}", id);
        var customer = await _repository.GetByIdAsync(id);
        return _mapper.Map<CustomerDto>(customer);
    }
}
```

### Service Registration
```csharp
// In Program.cs or Startup.cs
public void ConfigureServices(IServiceCollection services)
{
    // Transient - new instance every time
    services.AddTransient<IEmailService, EmailService>();
    
    // Scoped - one instance per request (web apps)
    services.AddScoped<ICustomerRepository, CustomerRepository>();
    
    // Singleton - one instance for application lifetime
    services.AddSingleton<ICacheService, MemoryCacheService>();
    
    // With interface
    services.AddScoped<ICustomerService, CustomerService>();
}
```

## XML Documentation Comments

### Required for Public APIs
```csharp
/// <summary>
/// Retrieves a customer by their unique identifier.
/// </summary>
/// <param name="customerId">The unique identifier of the customer.</param>
/// <param name="cancellationToken">Cancellation token to cancel the operation.</param>
/// <returns>
/// A <see cref="Customer"/> object if found; otherwise, null.
/// </returns>
/// <exception cref="ArgumentOutOfRangeException">
/// Thrown when <paramref name="customerId"/> is less than or equal to zero.
/// </exception>
/// <example>
/// <code>
/// var customer = await service.GetCustomerAsync(123);
/// if (customer != null)
/// {
///     Console.WriteLine($"Found: {customer.Name}");
/// }
/// </code>
/// </example>
public async Task<Customer?> GetCustomerAsync(
    int customerId, 
    CancellationToken cancellationToken = default)
{
    if (customerId <= 0)
    {
        throw new ArgumentOutOfRangeException(
            nameof(customerId), 
            "Customer ID must be greater than zero"
        );
    }
    
    return await _repository.FindAsync(customerId, cancellationToken);
}
```

## Testing Considerations

### Write Testable Code
```csharp
// Good - testable with dependency injection
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly IEmailService _emailService;
    private readonly IDateTimeProvider _dateTimeProvider;  // Abstraction for testing
    
    public OrderService(
        IOrderRepository repository,
        IEmailService emailService,
        IDateTimeProvider dateTimeProvider)
    {
        _repository = repository;
        _emailService = emailService;
        _dateTimeProvider = dateTimeProvider;
    }
    
    public async Task<Order> CreateOrderAsync(OrderRequest request)
    {
        var order = new Order
        {
            CustomerId = request.CustomerId,
            Items = request.Items,
            CreatedAt = _dateTimeProvider.UtcNow  // Can be mocked in tests
        };
        
        await _repository.AddAsync(order);
        await _emailService.SendOrderConfirmationAsync(order);
        
        return order;
    }
}

// Unit test example
[Fact]
public async Task CreateOrderAsync_ShouldSetCreatedAtTime()
{
    // Arrange
    var mockDateTime = new Mock<IDateTimeProvider>();
    var expectedTime = new DateTime(2025, 1, 1, 12, 0, 0, DateTimeKind.Utc);
    mockDateTime.Setup(x => x.UtcNow).Returns(expectedTime);
    
    var service = new OrderService(
        Mock.Of<IOrderRepository>(),
        Mock.Of<IEmailService>(),
        mockDateTime.Object
    );
    
    // Act
    var order = await service.CreateOrderAsync(new OrderRequest());
    
    // Assert
    Assert.Equal(expectedTime, order.CreatedAt);
}
```

## Performance Best Practices

### Use Span<T> and Memory<T> for Performance-Critical Code
```csharp
// Good - avoid allocations with Span<T>
public void ProcessData(ReadOnlySpan<byte> data)
{
    foreach (var b in data)
    {
        // Process without allocation
    }
}

// Stack allocation for small arrays
Span<int> numbers = stackalloc int[10];
for (int i = 0; i < numbers.Length; i++)
{
    numbers[i] = i * i;
}
```

### Avoid Boxing Value Types
```csharp
// Bad - boxing occurs
int value = 42;
object boxed = value;  // Boxing allocation
Console.WriteLine(boxed);  // Boxing in WriteLine(object)

// Good - avoid boxing
int value = 42;
Console.WriteLine(value);  // No boxing, uses WriteLine(int)

// Use generic collections to avoid boxing
List<int> numbers = new();  // No boxing
ArrayList oldStyle = new();  // Boxing on Add
```

### Use ValueTask for Hot Paths
```csharp
// Use ValueTask when result is often synchronous
public ValueTask<Customer?> GetCachedCustomerAsync(int id)
{
    // Check cache first (synchronous path)
    if (_cache.TryGetValue(id, out var customer))
    {
        return new ValueTask<Customer?>(customer);
    }
    
    // Fall back to async database call
    return new ValueTask<Customer?>(LoadFromDatabaseAsync(id));
}
```

## Code Analysis and Quality Tools

### Enable Static Analysis
```xml
<!-- In .csproj file -->
<PropertyGroup>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest</AnalysisLevel>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>
</PropertyGroup>

<!-- Add analyzer packages -->
<ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.NetAnalyzers" Version="8.0.0" />
    <PackageReference Include="SecurityCodeScan.VS2019" Version="5.6.7" />
    <PackageReference Include="SonarAnalyzer.CSharp" Version="9.0.0" />
</ItemGroup>
```

### EditorConfig Settings
Create `.editorconfig` file in project root:

```ini
root = true

[*.cs]
# Indentation
indent_style = space
indent_size = 4

# New line preferences
end_of_line = crlf
insert_final_newline = true

# Naming conventions
dotnet_naming_rule.interface_should_be_begins_with_i.severity = warning
dotnet_naming_rule.interface_should_be_begins_with_i.symbols = interface
dotnet_naming_rule.interface_should_be_begins_with_i.style = begins_with_i

# Code style rules
csharp_prefer_braces = true:warning
csharp_prefer_simple_using_statement = true:suggestion
csharp_style_namespace_declarations = file_scoped:warning
csharp_using_directive_placement = outside_namespace:warning

# Security rules
dotnet_diagnostic.CA2100.severity = error  # SQL injection
dotnet_diagnostic.CA3075.severity = error  # Insecure DTD processing
dotnet_diagnostic.CA5350.severity = error  # Weak cryptographic algorithms
```

## Common Anti-Patterns to Avoid

### Don't Use Magic Numbers
```csharp
// Bad - magic numbers
if (customer.Age > 18 && customer.AccountBalance > 1000)
{
    ApplyDiscount(0.15);
}

// Good - named constants
private const int MINIMUM_AGE = 18;
private const decimal MINIMUM_BALANCE = 1000m;
private const decimal PREMIUM_DISCOUNT = 0.15m;

if (customer.Age > MINIMUM_AGE && customer.AccountBalance > MINIMUM_BALANCE)
{
    ApplyDiscount(PREMIUM_DISCOUNT);
}
```

### Don't Swallow Exceptions
```csharp
// Bad - swallowing exceptions
try
{
    RiskyOperation();
}
catch
{
    // Silent failure - errors are hidden!
}

// Good - handle or rethrow
try
{
    RiskyOperation();
}
catch (SpecificException ex)
{
    _logger.LogError(ex, "Operation failed");
    throw;  // Rethrow to preserve stack trace
}
```

### Don't Return Null, Use Nullable Types or Option Pattern
```csharp
// Bad - null reference risk
public Customer GetCustomer(int id)
{
    var customer = _repository.Find(id);
    return customer;  // May return null!
}

// Good - explicit nullable return
public Customer? GetCustomer(int id)
{
    return _repository.Find(id);
}

// Better - use Result pattern
public Result<Customer> GetCustomer(int id)
{
    var customer = _repository.Find(id);
    return customer != null 
        ? Result<Customer>.Success(customer)
        : Result<Customer>.Failure("Customer not found");
}
```

## File Organization

### Namespace and Using Directives
```csharp
// Place using directives outside namespace (C# 10+)
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace MyCompany.MyProduct.Orders;  // File-scoped namespace (C# 10+)

public class OrderService
{
    // Class implementation
}
```

### Class Organization Order
```csharp
public class WellOrganizedClass
{
    // 1. Constants
    private const int MAX_RETRIES = 3;
    
    // 2. Static fields
    private static readonly ILogger _staticLogger;
    
    // 3. Private fields (with underscore prefix)
    private readonly IRepository _repository;
    private readonly ILogger<WellOrganizedClass> _logger;
    
    // 4. Constructors
    public WellOrganizedClass(IRepository repository, ILogger<WellOrganizedClass> logger)
    {
        _repository = repository;
        _logger = logger;
    }
    
    // 5. Public properties
    public string Name { get; set; }
    
    // 6. Public methods
    public void PublicMethod() { }
    
    // 7. Protected methods
    protected virtual void ProtectedMethod() { }
    
    // 8. Private methods
    private void PrivateMethod() { }
    
    // 9. Nested types (if necessary)
    private class NestedHelper { }
}
```

## Summary Checklist

- ✅ Use PascalCase for public members, camelCase with underscore for private fields
- ✅ Use Allman brace style (opening brace on new line)
- ✅ Use language keywords (`string`, `int`) instead of runtime types
- ✅ Use `var` only when type is obvious
- ✅ Always validate and sanitize user input
- ✅ Use parameterized queries to prevent SQL injection
- ✅ Encode output to prevent XSS
- ✅ Never hardcode secrets or credentials
- ✅ Use secure password hashing (PBKDF2, bcrypt, Argon2)
- ✅ Implement proper exception handling with specific exception types
- ✅ Use `async`/`await` for I/O operations
- ✅ Suffix async methods with "Async"
- ✅ Enable nullable reference types
- ✅ Use dependency injection for testability
- ✅ Write XML documentation for public APIs
- ✅ Enable static code analysis
- ✅ Use modern C# features appropriately (records, pattern matching, etc.)
- ✅ Follow SOLID principles
- ✅ Write unit tests for all business logic

## Additional Resources

- **Microsoft Documentation**: https://learn.microsoft.com/en-us/dotnet/csharp/
- **.NET Runtime Coding Style**: https://github.com/dotnet/runtime/blob/main/docs/coding-guidelines/coding-style.md
- **OWASP Security Guidelines**: https://owasp.org/www-project-top-ten/
- **C# Compiler (Roslyn) Guidelines**: https://github.com/dotnet/roslyn/blob/main/CONTRIBUTING.md
- **Framework Design Guidelines**: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/
