{-# LANGUAGE
OverloadedStrings,
TemplateHaskell,
RecordWildCards,
RankNTypes,
FlexibleInstances,
QuasiQuotes,
ScopedTypeVariables,
MultiParamTypeClasses,
FunctionalDependencies,
NoImplicitPrelude
  #-}


module Main (main) where


-- General
import BasePrelude hiding (Category)
-- Monads and monad transformers
import Control.Monad.State
-- Lenses
import Lens.Micro.Platform
-- Text
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Builder as TL
import Data.Text.Format hiding (format)
import qualified Data.Text.Format as Format
import qualified Data.Text.Format.Params as Format
import NeatInterpolation
-- Randomness
import System.Random
-- Web
import Lucid hiding (for_)
import Web.Spock hiding (get, text)
import qualified Web.Spock as Spock
import Network.Wai.Middleware.Static


-- | Unique id, used for many things – categories, items, and anchor ids.
-- Note that in HTML 5 using numeric ids for divs, spans, etc is okay.
type Uid = Int

randomUid :: MonadIO m => m Uid
randomUid = liftIO $ randomRIO (0, 10^(9::Int))

data ProCon = ProCon {
  _proConUid :: Uid,
  _proConContent :: Text }

makeFields ''ProCon

data ItemKind = HackageLibrary | Library | Unknown

data Item = Item {
  _itemUid  :: Uid,
  _itemName :: Text,
  _itemPros :: [ProCon],
  _itemCons :: [ProCon],
  _itemLink :: Maybe Text,
  _itemKind :: ItemKind }

makeFields ''Item

proConById :: Uid -> Lens' Item ProCon
proConById uid' = singular $
  (pros.each . filtered ((== uid') . view uid)) `failing`
  (cons.each . filtered ((== uid') . view uid))

data Category = Category {
  _categoryUid :: Uid,
  _categoryTitle :: Text,
  _categoryItems :: [Item] }

makeFields ''Category

data S = S {
  _categories :: [Category] }

makeLenses ''S

categoryById :: Uid -> Lens' S Category
categoryById uid' = singular $
  categories.each . filtered ((== uid') . view uid)

itemById :: Uid -> Lens' S Item
itemById uid' = singular $
  categories.each . items.each . filtered ((== uid') . view uid)

emptyState :: S
emptyState = S {
  _categories = [] }

sampleState :: S
sampleState = do
  let lensItem = Item {
        _itemUid = 12,
        _itemName = "lens",
        _itemPros = [ProCon 121 "the standard lenses library",
                     ProCon 122 "batteries included"],
        _itemCons = [ProCon 123 "huge"],
        _itemLink = Nothing,
        _itemKind = HackageLibrary }
  let microlensItem = Item {
        _itemUid = 13,
        _itemName = "microlens",
        _itemPros = [ProCon 131 "very small",
                     ProCon 132 "good for libraries"],
        _itemCons = [ProCon 133 "doesn't have advanced features"],
        _itemLink = Nothing,
        _itemKind = HackageLibrary }
  let lensesCategory = Category {
        _categoryUid = 1,
        _categoryTitle = "lenses",
        _categoryItems = [lensItem, microlensItem] }

  S {_categories = [lensesCategory]}

main :: IO ()
main = runSpock 8080 $ spockT id $ do
  middleware (staticPolicy (addBase "static"))
  stateVar <- liftIO $ newIORef sampleState
  let withS :: MonadIO m => State S a -> m a
      withS f = liftIO $ atomicModifyIORef' stateVar (swap . runState f)

  -- Render the main page.
  Spock.get root $ do
    s <- liftIO $ readIORef stateVar
    lucid $ renderRoot s

  -- The “/add” methods return rendered parts of the structure (added
  -- categories, changed items, etc) so that the Javascript part could take
  -- them and inject into the page. We don't want to duplicate rendering on
  -- server side and on client side.

  -- (category|item)/action
  -- (category|item)/id/action
  -- (category|item)/id/thing/action

  -- Create a new category, with its title submitted via a POST request.
  Spock.post "/category/add" $ do
    title' <- param' "title"
    uid' <- randomUid
    let newCategory = Category {
          _categoryUid = uid',
          _categoryTitle = title',
          _categoryItems = [] }
    withS $
      categories %= (++ [newCategory])
    lucid $ renderCategory newCategory

  -- Create a new library in the specified category, with the library name
  -- and category id submitted via a POST request.
  Spock.post ("/category" <//> var <//> "library/add") $ \catId -> do
    name' <- param' "name"
    uid' <- randomUid
    let newItem = Item {
          _itemUid  = uid',
          _itemName = name',
          _itemPros = [],
          _itemCons = [],
          _itemLink = Nothing,
          _itemKind = HackageLibrary }
    -- TODO: maybe do something if the category doesn't exist (e.g. has been
    -- already deleted)
    withS $
      categoryById catId . items %= (++ [newItem])
    lucid $ renderItem Normal newItem

  -- Add a pro (argument in favor of a library).
  Spock.post ("/item" <//> var <//> "pro/add") $ \itemId -> do
    content' <- param' "content"
    uid' <- randomUid
    let newThing = ProCon uid' content'
    withS $ do
      itemById itemId . pros %= (++ [newThing])
    lucid $ renderProCon Editable itemId newThing

  -- Add a con (argument against a library).
  Spock.post ("/item" <//> var <//> "con/add") $ \itemId -> do
    content' <- param' "content"
    uid' <- randomUid
    let newThing = ProCon uid' content'
    withS $ do
      itemById itemId . cons %= (++ [newThing])
    lucid $ renderProCon Editable itemId newThing

  -- Set the title of a category (returns rendered new title).
  Spock.post ("/category" <//> var <//> "title/set") $ \catId -> do
    title' <- param' "title"
    changedCategory <- withS $ do
      categoryById catId . title .= title'
      use (categoryById catId)
    lucid $ renderCategoryHeading changedCategory

  -- Return rendered title of a category.
  Spock.get ("/category" <//> var <//> "title/render-normal") $ \catId -> do
    category <- withS $ use (categoryById catId)
    lucid $ renderCategoryHeading category

  -- Return rendered title of a category the way it should look when the
  -- category is being edited.
  Spock.get ("/category" <//> var <//> "title/render-edit") $ \catId -> do
    category <- withS $ use (categoryById catId)
    lucid $ renderCategoryHeadingEdit category

  -- Return rendered item the way it should normally look.
  Spock.get ("/item" <//> var <//> "render-normal") $ \itemId -> do
    item <- withS $ use (itemById itemId)
    lucid $ renderItem Normal item

  -- Return rendered item the way it should look when it's editable.
  Spock.get ("/item" <//> var <//> "render-edit") $ \itemId -> do
    item <- withS $ use (itemById itemId)
    lucid $ renderItem Editable item

  -- Return rendered pro/con the way it should normally look.
  Spock.get ("/item" <//> var <//> "pro-con" <//> var <//> "render-normal") $
    \itemId thingId -> do
       thing <- withS $ use (itemById itemId . proConById thingId)
       lucid $ renderProCon Editable itemId thing

  -- Return rendered pro/con the way it should look when it's being edited.
  Spock.get ("/item" <//> var <//> "pro-con" <//> var <//> "render-edit") $
    \itemId thingId -> do
       thing <- withS $ use (itemById itemId . proConById thingId)
       lucid $ renderProCon InEdit itemId thing

  -- Change a pro/con.
  Spock.post ("/item" <//> var <//> "pro-con" <//> var <//> "set") $
    \itemId thingId -> do
       content' <- param' "content"
       changedThing <- withS $ do
         itemById itemId . proConById thingId . content .= content'
         use (itemById itemId . proConById thingId)
       lucid $ renderProCon Editable itemId changedThing

renderRoot :: S -> HtmlT IO ()
renderRoot s = do
  includeJS "https://ajax.googleapis.com/ajax/libs/jquery/2.2.0/jquery.min.js"
  includeCSS "/css.css"
  -- Include definitions of all Javascript functions that we have defined in
  -- this file.
  script_ $ T.unlines (map snd (allJSFunctions :: [(Text, Text)]))
  categoriesNode <- div_ [id_ "categories"] $ do
    mapM_ renderCategory (s ^. categories)
    thisNode
  input_ [type_ "text", placeholder_ "new category",
          submitFunc (js_addCategory (categoriesNode, js_this_value))]

renderCategoryHeading :: Category -> HtmlT IO ()
renderCategoryHeading category =
  h2_ $ do
    headerNode <- thisNode
    -- TODO: make category headings anchor links
    toHtml (category^.title)
    textButton "edit" $
      js_startCategoryHeadingEdit (headerNode, category^.uid)

renderCategoryHeadingEdit :: Category -> HtmlT IO ()
renderCategoryHeadingEdit category =
  h2_ $ do
    headerNode <- thisNode
    let handler = js_submitCategoryHeadingEdit
                    (headerNode, category^.uid, js_this_value)
    input_ [type_ "text", value_ (category^.title), submitFunc handler]
    textButton "cancel" $
      js_cancelCategoryHeadingEdit (headerNode, category^.uid)

renderCategory :: Category -> HtmlT IO ()
renderCategory category =
  div_ [id_ (tshow (category^.uid))] $ do
    renderCategoryHeading category
    itemsNode <- div_ [class_ "items"] $ do
      mapM_ (renderItem Normal) (category^.items)
      thisNode
    let handler = js_addLibrary (itemsNode, category^.uid, js_this_value)
    input_ [type_ "text", placeholder_ "new item", submitFunc handler]

-- TODO: when the link for a HackageLibrary isn't empty, show it separately
-- (as “site”), don't replace the Hackage link
renderItem
  :: Editable         -- ^ Show edit buttons?
  -> Item
  -> HtmlT IO ()
renderItem editable item =
  div_ [class_ "item", id_ (tshow (item^.uid))] $ do
    itemNode <- thisNode
    h3_ $ do
      itemHeader
      case editable of
        Normal -> textButton "edit" $
          js_enableItemEdit (itemNode, item^.uid)
        Editable -> textButton "edit off" $
          js_disableItemEdit (itemNode, item^.uid)
    div_ [class_ "pros-cons"] $ do
      div_ [class_ "pros"] $ do
        p_ "Pros:"
        case editable of
          Normal ->
            ul_ $ mapM_ (renderProCon Normal (item^.uid)) (item^.pros)
          Editable -> do
            listNode <- ul_ $ do
              mapM_ (renderProCon Editable (item^.uid)) (item^.pros)
              thisNode
            let handler = js_addPro (listNode, item^.uid, js_this_value)
            input_ [type_ "text", placeholder_ "add pro", submitFunc handler]
      div_ [class_ "cons"] $ do
        p_ "Cons:"
        case editable of
          Normal ->
            ul_ $ mapM_ (renderProCon Normal (item^.uid)) (item^.cons)
          Editable -> do
            listNode <- ul_ $ do
              mapM_ (renderProCon Editable (item^.uid)) (item^.cons)
              thisNode
            let handler = js_addCon (listNode, item^.uid, js_this_value)
            input_ [type_ "text", placeholder_ "add con", submitFunc handler]
  where
    hackageLink = format "https://hackage.haskell.org/package/{}"
                         [item^.name]
    itemHeader = case (item^.link, item^.kind) of
      (Just l, _) ->
        a_ [href_ l] (toHtml (item^.name))
      (Nothing, HackageLibrary) ->
        a_ [href_ hackageLink] (toHtml (item^.name))
      _otherwise -> toHtml (item^.name)

renderProCon :: Editable -> Uid -> ProCon -> HtmlT IO ()
renderProCon Normal _ proCon = li_ (toHtml (proCon^.content))
renderProCon Editable itemId proCon = li_ $ do
  this <- thisNode
  toHtml (proCon^.content)
  textButton "edit" $
    js_startProConEdit (this, itemId, proCon^.uid)
renderProCon InEdit itemId thing = li_ $ do
  this <- thisNode
  let handler = js_submitProConEdit
                  (this, itemId, thing^.uid, js_this_value)
  input_ [type_ "text", value_ (thing^.content), submitFunc handler]
  textButton "cancel" $
    js_cancelProConEdit (this, itemId, thing^.uid)

-- Utils

includeJS :: Monad m => Text -> HtmlT m ()
includeJS url = with (script_ "") [src_ url]

includeCSS :: Monad m => Text -> HtmlT m ()
includeCSS url = link_ [rel_ "stylesheet", type_ "text/css", href_ url]

submitFunc :: JS -> Attribute
submitFunc f = onkeyup_ $ format
  "if (event.keyCode == 13) {\
  \  {}\
  \  this.value = ''; }"
  [f]

-- Javascript

js_this_value :: JS
js_this_value = "this.value"

-- TODO: try to make them more type-safe somehow?

class JSFunction a where
  makeJSFunction
    :: Text          -- Name
    -> JS            -- Definition
    -> a

-- This generates function name
instance JSFunction Text where
  makeJSFunction fName _ = fName

-- This generates function definition and direct dependencies
instance JSFunction (Text, JS) where
  makeJSFunction fName fDef = (fName, fDef)

-- This generates a function that takes arguments and produces a Javascript
-- function call
instance Format.Params a => JSFunction (a -> JS) where
  makeJSFunction fName _ = \args -> do
    let argsText = map (TL.toStrict . TL.toLazyText) (Format.buildParams args)
    fName <> "(" <> T.intercalate "," argsText <> ");"

allJSFunctions :: JSFunction a => [a]
allJSFunctions = [
  js_replaceWithData, js_appendData,
  js_addLibrary, js_addCategory,
  js_startCategoryHeadingEdit, js_submitCategoryHeadingEdit, js_cancelCategoryHeadingEdit,
  js_addPro, js_addCon,
  js_enableItemEdit, js_disableItemEdit,
  js_startProConEdit, js_submitProConEdit, js_cancelProConEdit ]

js_replaceWithData :: JSFunction a => a
js_replaceWithData = makeJSFunction "replaceWithData" [text|
  function replaceWithData(node) {
    return function(data) {$(node).replaceWith(data); }; }
  |]

js_appendData :: JSFunction a => a
js_appendData = makeJSFunction "appendData" [text|
  function appendData(node) {
    return function(data) {$(node).append(data); }; }
  |]

-- | Create a new category.
js_addCategory :: JSFunction a => a
js_addCategory = makeJSFunction "addCategory" [text|
  function addCategory(node, s) {
    $.post("/category/add", {title: s})
     .done(appendData(node));
    }
  |]

-- | Add a new library to some category.
js_addLibrary :: JSFunction a => a
js_addLibrary = makeJSFunction "addLibrary" [text|
  function addLibrary(node, catId, s) {
    $.post("/category/"+catId+"/library/add", {name: s})
     .done(appendData(node));
    }
  |]

{- |
Start category heading editing (this happens when you click on “[edit]”).

This turns the heading into an editbox, and adds a [cancel] link.
-}
js_startCategoryHeadingEdit :: JSFunction a => a
js_startCategoryHeadingEdit = makeJSFunction "startCategoryHeadingEdit" [text|
  function startCategoryHeadingEdit(node, catId) {
    $.get("/category/"+catId+"/title/render-edit")
     .done(replaceWithData(node));
    }
  |]

{- |
Cancel category heading editing.

This turns the heading with the editbox back into a simple text heading.
-}
js_cancelCategoryHeadingEdit :: JSFunction a => a
js_cancelCategoryHeadingEdit = makeJSFunction "cancelCategoryHeadingEdit" [text|
  function cancelCategoryHeadingEdit(node, catId) {
    $.get("/category/"+catId+"/title/render-normal")
     .done(replaceWithData(node));
    }
  |]

{- |
Finish category heading editing (this happens when you submit the field).

This turns the heading with the editbox back into a simple text heading.
-}
js_submitCategoryHeadingEdit :: JSFunction a => a
js_submitCategoryHeadingEdit = makeJSFunction "submitCategoryHeadingEdit" [text|
  function submitCategoryHeadingEdit(node, catId, s) {
    $.post("/category/"+catId+"/title/set", {title: s})
     .done(replaceWithData(node));
    }
  |]

-- | Add a pro to some item.
js_addPro :: JSFunction a => a
js_addPro = makeJSFunction "addPro" [text|
  function addPro(node, itemId, s) {
    $.post("/item/"+itemId+"/pro/add", {content: s})
     .done(appendData(node));
    }
  |]

-- | Add a con to some item.
js_addCon :: JSFunction a => a
js_addCon = makeJSFunction "addCon" [text|
  function addCon(node, itemId, s) {
    $.post("/item/"+itemId+"/con/add", {content: s})
     .done(appendData(node));
    }
  |]

-- | Add “[edit]” buttons to everything in an item.
js_enableItemEdit :: JSFunction a => a
js_enableItemEdit = makeJSFunction "enableItemEdit" [text|
  function enableItemEdit (node, itemId) {
    $.get("/item/"+itemId+"/render-edit")
     .done(replaceWithData(node));
    }
  |]

-- | Remove “[edit]” buttons from everything in an item.
js_disableItemEdit :: JSFunction a => a
js_disableItemEdit = makeJSFunction "disableItemEdit" [text|
  function disableItemEdit (node, itemId) {
    $.get("/item/"+itemId+"/render-normal")
     .done(replaceWithData(node));
    }
  |]

js_startProConEdit :: JSFunction a => a
js_startProConEdit = makeJSFunction "startProConEdit" [text|
  function startProConEdit(node, itemId, thingId) {
    $.get("/item/"+itemId+"/pro-con/"+thingId+"/render-edit")
     .done(replaceWithData(node));
    }
  |]

js_cancelProConEdit :: JSFunction a => a
js_cancelProConEdit = makeJSFunction "cancelProConEdit" [text|
  function cancelProConEdit(node, itemId, thingId) {
    $.get("/item/"+itemId+"/pro-con/"+thingId+"/render-normal")
     .done(replaceWithData(node));
    }
  |]

js_submitProConEdit :: JSFunction a => a
js_submitProConEdit = makeJSFunction "submitProConEdit" [text|
  function submitProConEdit(node, itemId, thingId, s) {
    $.post("/item/"+itemId+"/pro-con/"+thingId+"/set", {content: s})
     .done(replaceWithData(node));
    }
  |]

-- When adding a function, don't forget to add it to 'allJSFunctions'!

type JS = Text

-- A text button looks like “[cancel]”
textButton
  :: Text         -- ^ Button text
  -> JS           -- ^ Onclick handler
  -> HtmlT IO ()
textButton caption handler =
  span_ [class_ "textButton"] $
    a_ [href_ "javascript:void(0)", onclick_ handler] (toHtml caption)

type JQuerySelector = Text

thisNode :: HtmlT IO JQuerySelector
thisNode = do
  uid' <- randomUid
  span_ [id_ (tshow uid')] mempty
  return (T.pack (show (format ":has(> #{})" [uid'])))

lucid :: HtmlT IO a -> ActionT IO a
lucid h = do
  htmlText <- liftIO (renderTextT h)
  html (TL.toStrict htmlText)

-- | Format a string (a bit 'Text.Printf.printf' but with different syntax).
format :: Format.Params ps => Format -> ps -> Text
format f ps = TL.toStrict (Format.format f ps)

tshow :: Show a => a -> Text
tshow = T.pack . show

data Editable = Normal | Editable | InEdit
