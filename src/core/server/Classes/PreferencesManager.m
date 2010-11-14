#import "PreferencesManager.h"
#include <sys/time.h>

@implementation PreferencesManager

// ----------------------------------------
- (void) addToDefault:(NSXMLElement*)element
{
  for (NSXMLElement* e in [element elementsForName : @"sysctl"]) {
    NSXMLNode* attr_default = [e attributeForName:@"default"];
    if (! attr_default) continue;

    [default_ setObject:[NSNumber numberWithInt:[[attr_default stringValue] intValue]] forKey:[e stringValue]];
  }

  for (NSXMLElement* e in [element elementsForName : @"list"]) {
    [self addToDefault:e];
  }
  for (NSXMLElement* e in [element elementsForName : @"item"]) {
    [self addToDefault:e];
  }
}

- (void) setDefault
{
  NSString* xmlpath = @"/Library/org.pqrs/KeyRemap4MacBook/prefpane/number.xml";
  NSURL* xmlurl = [NSURL fileURLWithPath:xmlpath];
  NSXMLDocument* xmldocument = [[[NSXMLDocument alloc] initWithContentsOfURL:xmlurl options:0 error:NULL] autorelease];
  if (xmldocument) {
    [self addToDefault:[xmldocument rootElement]];
  }
}

// ----------------------------------------
- (void) loadSelectedDictionary
{
  @synchronized(self) {
    if (value_) {
      [value_ release];
    }
    value_ = [[NSMutableDictionary alloc] initWithCapacity:0];

    NSArray* configList = [self configlist_getConfigList];
    if (! configList) return;

    NSUInteger selectedIndex = (NSUInteger)[self configlist_selectedIndex];
    if (selectedIndex >= [configList count]) return;

    NSDictionary* configListItem = [configList objectAtIndex:selectedIndex];
    if (! configListItem) return;

    NSString* identifier = [configListItem objectForKey:@"identify"];
    if (! identifier) return;

    NSDictionary* dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
    if (! dict) return;

    [value_ addEntriesFromDictionary:dict];
  }
}

- (id) init
{
  [super init];

  default_ = [[NSMutableDictionary alloc] initWithCapacity:0];
  [self setDefault];
  [self loadSelectedDictionary];

  essential_config_index_ = [[NSArray alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"include.bridge_essential_config_index" ofType:@"plist"]];

  serverconnection_ = [NSConnection new];
  [serverconnection_ setRootObject:self];
  [serverconnection_ registerName:@"org.pqrs.KeyRemap4MacBook"];

  return self;
}

- (void) dealloc
{
  if (default_) {
    [default_ release];
  }
  if (value_) {
    [value_ release];
  }
  if (essential_config_index_) {
    [essential_config_index_ release];
  }
  if (serverconnection_) {
    [serverconnection_ release];
  }
  [super dealloc];
}

// ----------------------------------------------------------------------
- (int) value:(NSString*)name
{
  int v = 0;
  @synchronized(self) {
    NSNumber* number = [value_ objectForKey:name];
    if (! number) {
      number = [default_ objectForKey:name];
    }

    if (number) {
      v = [number intValue];
    }
  }
  return v;
}

- (NSArray*) essential_config
{
  NSMutableArray* a = [[[NSMutableArray alloc] initWithCapacity:0] autorelease];
  @synchronized(self) {
    if (essential_config_index_) {
      for (NSString* name in essential_config_index_) {
        [a addObject:[NSNumber numberWithInt:[self value:name]]];
      }
    }
  }
  return a;
}

// ----------------------------------------------------------------------
- (NSInteger) configlist_selectedIndex
{
  return [[NSUserDefaults standardUserDefaults] integerForKey:@"selectedIndex"];
}

- (NSString*) configlist_selectedName
{
  return [self configlist_name:[self configlist_selectedIndex]];
}

- (NSArray*) configlist_getConfigList
{
  return [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
}

- (NSUInteger) configlist_count
{
  NSArray* a = [self configlist_getConfigList];
  if (! a) return 0;
  return [a count];
}

- (NSString*) configlist_name:(NSInteger)rowIndex
{
  NSString* name = nil;

  @synchronized(self) {
    NSArray* list = [self configlist_getConfigList];
    if (list) {
      if (0 <= rowIndex && (NSUInteger)(rowIndex) < [list count]) {
        NSDictionary* dict = [list objectAtIndex:rowIndex];
        if (dict) {
          name = [dict objectForKey:@"name"];
        }
      }
    }
  }

  return name;
}

- (void) configlist_select:(NSInteger)newindex
{
  if (newindex < 0) return;
  if (newindex == [self configlist_selectedIndex]) return;

  NSArray* list = [self configlist_getConfigList];
  if (! list) return;
  if ((NSUInteger)(newindex) >= [list count]) return;

  NSUserDefaults* userdefaults = [NSUserDefaults standardUserDefaults];

  [userdefaults setInteger:newindex forKey:@"selectedIndex"];
  [self loadSelectedDictionary];

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

- (void) configlist_setName:(NSInteger)rowIndex name:(NSString*)name
{
  if ([name length] == 0) return;

  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (! a) return;
  if (rowIndex < 0 || (NSUInteger)(rowIndex) >= [a count]) return;

  NSDictionary* d = [a objectAtIndex:rowIndex];
  if (! d) return;

  NSMutableDictionary* md = [NSMutableDictionary dictionaryWithDictionary:d];
  if (! md) return;
  [md setObject:name forKey:@"name"];

  NSMutableArray* ma = [NSMutableArray arrayWithArray:a];
  if (! ma) return;
  [ma replaceObjectAtIndex:rowIndex withObject:md];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

- (void) configlist_append
{
  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (! a) return;
  NSMutableArray* ma = [NSMutableArray arrayWithArray:a];
  if (! ma) return;

  struct timeval tm;
  gettimeofday(&tm, NULL);
  NSString* identifier = [NSString stringWithFormat:@"config_%d_%d", tm.tv_sec, tm.tv_usec];

  NSMutableDictionary* md = [NSMutableDictionary dictionaryWithCapacity:0];
  [md setObject:@"NewItem" forKey:@"name"];
  [md setObject:identifier forKey:@"identify"];

  [ma addObject:md];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

- (void) configlist_delete:(NSInteger)rowIndex
{
  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (! a) return;

  if (rowIndex < 0 || (NSUInteger)(rowIndex) >= [a count]) return;
  if ([a count] <= 1) return;

  NSMutableArray* ma = [NSMutableArray arrayWithArray:a];
  if (! ma) return;

  [ma removeObjectAtIndex:(NSUInteger)(rowIndex)];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

- (BOOL) isStatusbarEnable
{
  // If the key does not exist, treat as YES.
  id object = [[NSUserDefaults standardUserDefaults] objectForKey:@"isStatusbarEnable"];
  if (! object) return YES;

  NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:@"isStatusbarEnable"];
  return value ? YES : NO;
}

- (BOOL) isShowSettingNameInStatusBar
{
  NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:@"isShowSettingNameInStatusBar"];
  return value ? YES : NO;
}

- (void) toggleStatusbarEnable
{
  if ([self isStatusbarEnable]) {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"isStatusbarEnable"];
  } else {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"isStatusbarEnable"];
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

- (void) toggleShowSettingNameInStatusBar
{
  if ([self isShowSettingNameInStatusBar]) {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"isShowSettingNameInStatusBar"];
  } else {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"isShowSettingNameInStatusBar"];
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:@"PreferencesChanged" object:nil];
}

@end
