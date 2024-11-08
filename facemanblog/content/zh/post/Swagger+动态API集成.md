+++
date = '2024-11-08T17:18:05+08:00'
draft = false
title = 'Swagger+动态API集成'
featured_image = '/images/esmeralda.jpg'
+++

## 集成Swagger

1. 首先，在你的.NET Core项目中安装需要的包。你可以通过NuGet包管理器来安装它，也可以直接复制粘贴安装，以下是包名和版本。

```csharp
		<PackageReference Include="Swashbuckle.AspNetCore" Version="6.4.0" />
		<PackageReference Include="Swashbuckle.AspNetCore.Filters" Version="8.0.2" />
```
2. .Net 6以后取消了StartUp，配置都在Program中，这里采用新写法。

```csharp
var builder = WebApplication.CreateBuilder(args);
// 配置文件读取
var basePath = AppContext.BaseDirectory;
var config = new ConfigurationBuilder()
                .SetBasePath(basePath)
                .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                .Build();
                
#region 添加Swagger文档服务

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    //添加响应头信息。它可以帮助开发者查看 API 响应中包含的 HTTP 头信息，从而更好地理解 API 的行为。
    options.OperationFilter<AddResponseHeadersFilter>();
    //摘要中添加授权信息。它会在每个需要授权的操作旁边显示一个锁图标，提醒开发者该操作需要身份验证。
    options.OperationFilter<AppendAuthorizeToSummaryOperationFilter>();
    //加安全需求信息。它会根据 API 的安全配置（如 OAuth2、JWT 等）自动生成相应的安全需求描述，帮助开发者了解哪些操作需要特定的安全配置。
    options.OperationFilter<SecurityRequirementsOperationFilter>();
    //options.DocumentFilter<RemoveAppSuffixFilter>();
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "xxxFrameWork API",
        Version = "v1",
        Description = "xxxFrameWork API 接口文档",
        Contact = new OpenApiContact()
        {
            Name = "xxxxx",
            Email = "xxxxx@qq.com",
            Url = new Uri("https://github.com/xxxxx")
        }
    });
});

#endregion 添加Swagger文档服务

//开发环境才开启文档。
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        //配置Endpoint路径和文档标题
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "v1 Docs");
        //配置路由前缀，RoutePrefix是Swagger UI的根路径。
        //options.RoutePrefix = String.Empty;
        //设置默认模型展开深度。默认值为3，可以设置成-1以完全展开所有模型。
        //options.DefaultModelExpandDepth(-1);
        // 启用深链接功能后，用户可以直接通过URL访问特定的API操作或模型，而不需要手动导航到相应的位置。
        options.EnableDeepLinking();
        options.DocExpansion(DocExpansion.None); //swagger文档展开方式，none为折叠，list为列表
    });
}
```

## 动态API
Swagger文档的原理是扫描控制器来生成，动态API则是自定义类控制器，然后让接口继承，自定义控制器识别规则，实现思路：
1. 定义一个接口或特性用来标识这是个控制器，Mvc中实现的核心是ControllerFeatureProvider类，重写IsController的判断逻辑。
2. 继承IApplicationModelConvention重写Apply，如果是继承了自定义的控制器接口就根据规则标记Http请求类型。比如Abp中继承了IApplicationService接口，Swagger会自动识别,且遵循约定大于规范原则，将Get开头的请求都默认是Get请求，Del开头的请求默认是Delete请求。
3. 配置应用程序部分管理器，添加自定义的控制器特性提供程序
4. 配置MvcOptions，添加自定义的应用程序模型约定

模仿Abp的实现
### 创建IApplicationService用来标识自定义控制器的接口或特性
```csharp
 /// <summary>
 /// 动态WebAPI接口
 /// </summary>
 public class IApplicationService
 {
 }
 
  /// <summary>
  /// 动态WebAPI特性
  /// </summary>
  [AttributeUsage(AttributeTargets.Class, Inherited = true)]
  public class DynamicWebApiAttribute : Attribute
  {
  }
```
创建ApplicationServiceControllerFeatureProvider类来继承ControllerFeatureProvider类
```csharp
/// <summary>
/// 自定义控制器特性提供程序，用于将实现了 IApplicationService 接口的类识别为控制器。
/// </summary>
public class ApplicationServiceControllerFeatureProvider : ControllerFeatureProvider
{
    /// <summary>
    /// 判断给定的类型是否为控制器。
    /// </summary>
    /// <param name="typeInfo">要判断的类型信息。</param>
    /// <returns>如果类型是控制器，则返回 true；否则返回 false。</returns>
    protected override bool IsController(TypeInfo typeInfo)
    {
        // 检查类型是否实现了 IApplicationService 接口
        if (typeof(IApplicationService).IsAssignableFrom(typeInfo))
        {
            // 检查类型是否满足以下条件：
            var type = typeInfo.AsType();
            if ((typeof(IApplicationService).IsAssignableFrom(type) || //判断是否继承ICoreDynamicController接口
                type.IsDefined(typeof(DynamicWebApiAttribute), true) ||// 判断是否标记了DynamicAPIAttribute特性
                 type.BaseType == typeof(Controller)) &&
                typeInfo.IsPublic && !typeInfo.IsAbstract && !typeInfo.IsGenericType && !typeInfo.IsInterface)//必须是Public、不能是抽象类、必须是非泛型的
            {
                return true;
            }
        }
        // 如果不满足上述条件，则返回 false
        return false;
    }
}
```
### 创建HttpMethodConfigure配置类

```csharp
	public class HttpMethodConfigure
    {
        public string MethodKey { get; set; }
        public List<string> MethodVal { get; set; }
    }
```
### 创建ApplicationServiceConvention继承IApplicationModelConvention

```csharp
/// <summary>
/// 自定义应用程序模型约定，用于配置实现了 IApplicationService 接口的控制器。
/// </summary>
public class ApplicationServiceConvention : IApplicationModelConvention
{
    private IConfiguration _configuration;
    private List<HttpMethodConfigure> httpMethods = new();
    public ApplicationServiceConvention(IConfiguration configuration)
    {
        _configuration = configuration;
        httpMethods = _configuration.GetSection("HttpMethodInfo").Get<List<HttpMethodConfigure>>();
    }

    /// <summary>
    /// 应用约定
    /// </summary>
    /// <param name="application"></param>
    public void Apply(ApplicationModel application)
    {
        //循环每一个控制器信息
        foreach (var controller in application.Controllers)
        {
            var controllerType = controller.ControllerType.AsType();
            //是否继承IApplicationService接口
            if (typeof(IApplicationService).IsAssignableFrom(controllerType))
            {
                //Actions就是接口的方法
                foreach (var item in controller.Actions)
                {
                    ConfigureSelector(controller.ControllerName, item);
                }
            }
        }
    }

    /// <summary>
    /// 配置选择器
    /// </summary>
    /// <param name="controllerName"></param>
    /// <param name="action"></param>
    private void ConfigureSelector(string controllerName, ActionModel action)
    {
        //如果属性路由模型为空，则移除
        for (int i = 0; i < action.Selectors.Count; i++)
        {
            if (action.Selectors[i].AttributeRouteModel is null)
            {
                action.Selectors.Remove(action.Selectors[i]);
            }
        }
            //去除路径中的AppService后缀
            if (controllerName.EndsWith("AppService"))
            {
                controllerName = controllerName.Substring(0, controllerName.Length - 10);
            }
        //如果有选择器，则遍历选择器，添加默认路由
        if (action.Selectors.Any())
        {
            foreach (var item in action.Selectors)
            {
                var routePath = string.Concat("api/", controllerName + "/", action.ActionName).Replace("//", "/");
                var routeModel = new AttributeRouteModel(new RouteAttribute(routePath));
                //如果没有设置路由，则添加路由
                if (item.AttributeRouteModel == null)
                {
                    item.AttributeRouteModel = routeModel;
                }
            }
        }
        //如果没有选择器，则创建一个选择器并添加。
        else
        {
            action.Selectors.Add(CreateActionSelector(controllerName, action));
        }
    }

    /// <summary>
    /// 创建Action选择器
    /// </summary>
    /// <param name="controllerName"></param>
    /// <param name="action"></param>
    /// <returns></returns>
    private SelectorModel CreateActionSelector(string controllerName, ActionModel action)
    {
        var selectorModel = new SelectorModel();
        var actionName = action.ActionName;
        string httpMethod = string.Empty;
        //是否有HttpMethodAttribute
        var routeAttributes = action.ActionMethod.GetCustomAttributes(typeof(HttpMethodAttribute), false);
        //如果标记了HttpMethodAttribute
        if (routeAttributes != null && routeAttributes.Any())
        {
            httpMethod = routeAttributes.SelectMany(m => (m as HttpMethodAttribute).HttpMethods).ToList().Distinct().FirstOrDefault();
        }
        else
        {
            //大写方法名
            var methodName = action.ActionMethod.Name.ToUpper();
            //遍历HttpMethodInfo配置，匹配方法名
            foreach (var item in httpMethods)
            {
                foreach (var method in item.MethodVal)
                {
                    if (methodName.StartsWith(method))
                    {
                        httpMethod = item.MethodKey;
                        break;
                    }

                }
            }
            //如果没有找到对应的HttpMethod，默认使用POST
            if (httpMethod == string.Empty)
            {
                httpMethod = "POST";
            }
        }

        return ConfigureSelectorModel(selectorModel, action, controllerName, httpMethod);
    }

    /// <summary>
    /// 配置选择器模型
    /// </summary>
    /// <param name="selectorModel"></param>
    /// <param name="action"></param>
    /// <param name="controllerName"></param>
    /// <param name="httpMethod"></param>
    /// <returns></returns>
    public SelectorModel ConfigureSelectorModel(SelectorModel selectorModel, ActionModel action, string controllerName, string httpMethod)
    {
        var routePath = string.Concat("api/", controllerName + "/", action.ActionName).Replace("//", "/");
        //给此选择器添加路由
        selectorModel.AttributeRouteModel = new AttributeRouteModel(new RouteAttribute(routePath));
        //添加HttpMethod
        selectorModel.ActionConstraints.Add(new HttpMethodActionConstraint(new[] { httpMethod }));
        return selectorModel;
    }

}
```
### 创建RemoveAppFilter过滤类

```csharp
public class RemoveAppFilter : IDocumentFilter
{
    public void Apply(OpenApiDocument swaggerDoc, DocumentFilterContext context)
    {
        // 去掉控制器分类中的 "App" 后缀
        foreach (var path in swaggerDoc.Paths.Values)
        {
            foreach (var operation in path.Operations.Values)
            {
                var tags = operation.Tags.Select(tag => new OpenApiTag
                {
                    Name = tag.Name.Replace("AppService", "", StringComparison.OrdinalIgnoreCase),
                    Description = tag.Description
                }).ToList();

                operation.Tags.Clear();
                foreach (var tag in tags)
                {
                    operation.Tags.Add(tag);
                }
            }
        }
    }
}
```
### 创建DynamicWebApiExtensions

```csharp
 /// <summary>
 /// 动态WebAPI扩展类，用于在ASP.NET Core应用程序中添加动态WebAPI功能。
 /// </summary>
 public static class DynamicWebApiExtensions
 {
     /// <summary>
     /// 为IMvcBuilder添加动态WebAPI功能。
     /// </summary>
     /// <param name="builder">IMvcBuilder实例。</param>
     /// <returns>IMvcBuilder实例。</returns>
     public static IMvcBuilder AddDynamicWebApi(this IMvcBuilder builder, IConfiguration configuration)
     {
         if (builder == null)
         {
             throw new ArgumentNullException(nameof(builder));
         }

         // 配置应用程序部分管理器，添加自定义的控制器特性提供程序
         builder.ConfigureApplicationPartManager(applicationPartManager =>
         {
             applicationPartManager.FeatureProviders.Add(new ApplicationServiceControllerFeatureProvider());
         });

         // 配置MvcOptions，添加自定义的应用程序模型约定
         builder.Services.Configure<MvcOptions>(options =>
         {
             options.Conventions.Add(new ApplicationServiceConvention(configuration));
         });

         return builder;
     }

     /// <summary>
     /// 为IMvcCoreBuilder添加动态WebAPI功能。
     /// </summary>
     /// <param name="builder">IMvcCoreBuilder实例。</param>
     /// <returns>IMvcCoreBuilder实例。</returns>
     public static IMvcCoreBuilder AddDynamicWebApi(this IMvcCoreBuilder builder, IConfiguration configuration)
     {
         if (builder == null)
         {
             throw new ArgumentNullException(nameof(builder));
         }

         // 配置应用程序部分管理器，添加自定义的控制器特性提供程序
         builder.ConfigureApplicationPartManager(applicationPartManager =>
         {
             applicationPartManager.FeatureProviders.Add(new ApplicationServiceControllerFeatureProvider());
         });

         // 配置MvcOptions，添加自定义的应用程序模型约定
         builder.Services.Configure<MvcOptions>(options =>
         {
             options.Conventions.Add(new ApplicationServiceConvention(configuration));
         });

         return builder;
     }
 }
```
### Program中配置

```csharp
//注册动态API服务
builder.Services.AddControllers().AddDynamicWebApi(builder.Configuration);
//必须要加，不然断点进不来
app.MapControllers();

builder.Services.AddSwaggerGen(options =>
{
    ///其他代码
    options.DocumentFilter<RemoveAppFilter>();
    ///其他代码
});

```

### 在Appsettings配置http请求类型匹配规则

```csharp
"HttpMethodInfo": [
  {
    "MethodKey": "Get",
    "MethodVal": [ "GET", "QUERY" ]
  },
  {
    "MethodKey": "Post",
    "MethodVal": [ "CREATE", "SAVE", "INSERT", "ADD" ]
  },
  {
    "MethodKey": "Put",
    "MethodVal": [ "UPDATE", "EDIT" ]
  },
  {
    "MethodKey": "Delete",
    "MethodVal": [ "Delete", "REMOVE" ]
  }
]
```
### 创建测试类

```csharp
 public class Test : IApplicationService
 {
     /// <summary>
     ///领域层注释测试接口
     /// </summary>
     /// <returns></returns>
     public string Hello()
     {
         return "Hello from Class1";
     }

     public string Get()
     {
         return "Get from Class1";
     }
 }
```
![在这里插入图片描述](https://i-blog.csdnimg.cn/direct/7a406a66b5a0474095e1a7fc40d1ce14.png)

## 将动态API配置Swagger文档注释
1. 类库配置中设置xml文件生成地址

```csharp
 <GenerateDocumentationFile>True</GenerateDocumentationFile>
 <DocumentationFile>bin\Debug\FlyFramework.Core.xml</DocumentationFile>
```
2. 在Host中的wwwroot创建ApiDocs文件夹
3. Host主机配置xml文件复制地址，生成的xml文件会复制到对应的地址。


```csharp
<ApiDocDir>wwwroot\ApiDocs</ApiDocDir>

<!--在构建项目后，复制所有以FlyFramework开头的XML文档文件到指定的API文档目录。这通常用于将生成的XML文档文件（例如API注释）整理到一个目录中，便于进一步的处理或发布。这种做法可以适合于生成API文档如Swagger时的使用场景。-->
<Target Name="CopyXmlDocFileForBuild" AfterTargets="Build">
	<ItemGroup>
	
		<!--Include="@(ReferencePath->'%(RootDir)%(Directory)%(Filename).xml')"：这行表示从所有项目引用（ReferencePath）的路径中收集以.xml为扩展名的文件。这些文件通常是生成的XML文档文件。-->
		<!--Condition="$([System.String]::new('%(FileName)').StartsWith('FlyFramework'))"：此条件用于过滤文件，仅包括文件名以FlyFramework开头的XML文档文件。这保证只有相关的文档文件被选择。-->
		<XmlDocFiles Include="@(ReferencePath->'%(RootDir)%(Directory)%(Filename).xml')" Condition="$([System.String]::new('%(FileName)').StartsWith('FlyFramework'))" />
	</ItemGroup>
	
	<!--SourceFiles="@(XmlDocFiles)"：指定要复制的源文件为上一步中定义的XmlDocFiles集合。-->
	<!--`Condition="Exists('%(FullPath)')"：确保复制前源文件存在，这是一种安全检查。-->
	<!--DestinationFolder="$(ApiDocDir)"：目的地文件夹为$(ApiDocDir)，这个属性之前已经在项目文件中定义，指向存放API文档的目录。-->
	<!--SkipUnchangedFiles="true"：此选项表示只有发生变化的文件会被复制，这可以提高效率，避免不必要的复制操作。-->
	<Copy SourceFiles="@(XmlDocFiles)" Condition="Exists('%(FullPath)')" DestinationFolder="$(ApiDocDir)" SkipUnchangedFiles="true" />
</Target>

```
4. 在AddSwaggerGen增加配置

```csharp
//遍历所有xml并加载
var binXmlFiles =
    new DirectoryInfo(Path.Join(builder.Environment.WebRootPath, "ApiDocs"))
        .GetFiles("*.xml", SearchOption.TopDirectoryOnly);
foreach (var filePath in binXmlFiles.Select(item => item.FullName))
{
    options.IncludeXmlComments(filePath, true);
}
```

## 致谢
思路参考的大佬文章，大佬是从源码角度解释，我写这篇偏新手向，做了些拓展，原文指路：[.Net Core后端架构实战【2-实现动态路由与Dynamic API】 - 江北、 - 博客园 (cnblogs.com)](https://www.cnblogs.com/zhangnever/p/17131504.html)