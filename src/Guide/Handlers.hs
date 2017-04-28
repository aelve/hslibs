{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}


{- |
All rest API handlers.
-}
module Guide.Handlers
(
  methods,
  adminMethods,
)
where


import Imports

-- Containers
import qualified Data.Map as M
import qualified Data.Set as S
-- Feeds
import qualified Text.Feed.Types as Feed
import qualified Text.Feed.Util  as Feed
import qualified Text.Atom.Feed  as Atom
-- Text
import qualified Data.Text.All as T
import qualified Data.Text.Lazy.All as TL
-- JSON
import qualified Data.Aeson as A
-- Web
import Web.Spock hiding (head, get, text)
import qualified Web.Spock as Spock
import Web.Spock.Lucid
import Network.Wai.Middleware.Cors
import Lucid hiding (for_)
import qualified Network.HTTP.Types.Status as HTTP

import Guide.ServerStuff
import Guide.Config
import Guide.Cache
import Guide.Merge
import Guide.Markdown
import Guide.State
import Guide.Types
import Guide.Utils
import Guide.Views
import Guide.Views.Utils (categoryLink)


methods :: SpockM () () ServerState ()
methods = do
  apiMethods
  renderMethods
  setMethods
  addMethods
  otherMethods

apiMethods :: SpockM () () ServerState ()
apiMethods = Spock.subcomponent "api" $ do
  middleware simpleCors
  Spock.get "all-categories" $ do
    grands <- groupWith (view group_) <$> dbQuery GetCategories
    let jsonCat cat = M.fromList [
          ("title" :: Text,
             cat^.title),
          ("link" :: Text,
             categoryLink cat),
          ("uid" :: Text,
             uidToText (cat^.uid))
          ]
    let jsonGrand grand = A.object
          [ "title" A..=
                (grand^?!_head.group_)
          , "finished" A..=
                map jsonCat
                (filter ((== CategoryFinished) . view status) grand)
          , "wip" A..=
                map jsonCat
                (filter ((== CategoryWIP) . view status) grand)
          , "stubs" A..=
                map jsonCat
                (filter ((== CategoryStub) . view status) grand)
          ]
    json (map jsonGrand grands)
  
renderMethods :: SpockM () () ServerState ()
renderMethods = Spock.subcomponent "render" $ do
  -- Notes for a category
  Spock.get (categoryVar <//> "notes") $ \catId -> do
    category <- dbQuery (GetCategory catId)
    lucidIO $ renderCategoryNotes category
  -- Item colors
  Spock.get (itemVar <//> "colors") $ \itemId -> do
    item <- dbQuery (GetItem itemId)
    category <- dbQuery (GetCategoryByItem itemId)
    let hue = getItemHue category item
    json $ M.fromList [("light" :: Text, hueToLightColor hue),
                       ("dark" :: Text, hueToDarkColor hue)]
  -- Item info
  Spock.get (itemVar <//> "info") $ \itemId -> do
    item <- dbQuery (GetItem itemId)
    category <- dbQuery (GetCategoryByItem itemId)
    lucidIO $ renderItemInfo category item
  -- Item description
  Spock.get (itemVar <//> "description") $ \itemId -> do
    item <- dbQuery (GetItem itemId)
    lucidIO $ renderItemDescription item
  -- Item ecosystem
  Spock.get (itemVar <//> "ecosystem") $ \itemId -> do
    item <- dbQuery (GetItem itemId)
    lucidIO $ renderItemEcosystem item
  -- Item notes
  Spock.get (itemVar <//> "notes") $ \itemId -> do
    item <- dbQuery (GetItem itemId)
    category <- dbQuery (GetCategoryByItem itemId)
    lucidIO $ renderItemNotes category item

setMethods :: SpockM () () ServerState ()
setMethods = Spock.subcomponent "set" $ do
  Spock.post (categoryVar <//> "info") $ \catId -> do
    -- TODO: [easy] add a cross-link saying where the form is handled in the
    -- code and other notes saying where stuff is rendered, etc
    title' <- T.strip <$> param' "title"
    group' <- T.strip <$> param' "group"
    prosConsEnabled'  <- (Just ("on" :: Text) ==) <$>
                         param "pros-cons-enabled"
    ecosystemEnabled' <- (Just ("on" :: Text) ==) <$>
                         param "ecosystem-enabled"
    notesEnabled'     <- (Just ("on" :: Text) ==) <$>
                         param "notes-enabled"
    status' <- do
      statusName :: Text <- param' "status"
      return $ case statusName of
        "finished" -> CategoryFinished
        "wip"      -> CategoryWIP
        "stub"     -> CategoryStub
        other      -> error ("unknown category status: " ++ show other)
    -- Modify the category
    -- TODO: actually validate the form and report errors
    uncache (CacheCategoryInfo catId) $ do
      unless (T.null title') $ do
        (edit, _) <- dbUpdate (SetCategoryTitle catId title')
        addEdit edit
      unless (T.null group') $ do
        (edit, _) <- dbUpdate (SetCategoryGroup catId group')
        addEdit edit
      do (edit, _) <- dbUpdate (SetCategoryStatus catId status')
         addEdit edit
      do oldEnabledSections <- view enabledSections <$> dbQuery (GetCategory catId)
         let newEnabledSections = S.fromList . concat $
               [ [ItemProsConsSection  | prosConsEnabled']
               , [ItemEcosystemSection | ecosystemEnabled']
               , [ItemNotesSection     | notesEnabled'] ]
         (edit, _) <- dbUpdate $
                      ChangeCategoryEnabledSections catId
                        (newEnabledSections S.\\ oldEnabledSections)
                        (oldEnabledSections S.\\ newEnabledSections)
         addEdit edit
    -- After all these edits we can render the category header
    category <- dbQuery (GetCategory catId)
    lucidIO $ renderCategoryInfo category
  -- Notes for a category
  Spock.post (categoryVar <//> "notes") $ \catId -> do
    original <- param' "original"
    content' <- param' "content"
    modified <- view (notes.mdText) <$> dbQuery (GetCategory catId)
    if modified == original
      then do
        category <- uncache (CacheCategoryNotes catId) $ do
          (edit, category) <- dbUpdate (SetCategoryNotes catId content')
          addEdit edit
          return category
        lucidIO $ renderCategoryNotes category
      else do
        setStatus HTTP.status409
        json $ M.fromList [
          ("modified" :: Text, modified),
          ("merged" :: Text, merge original content' modified)]
  -- Item info
  Spock.post (itemVar <//> "info") $ \itemId -> do
    -- TODO: [easy] add a cross-link saying where the form is handled in the
    -- code and other notes saying where stuff is rendered, etc
    name' <- T.strip <$> param' "name"
    link' <- T.strip <$> param' "link"
    kind' <- do
      kindName :: Text <- param' "kind"
      hackageName' <- (\x -> if T.null x then Nothing else Just x) <$>
                      param' "hackage-name"
      return $ case kindName of
        "library" -> Library hackageName'
        "tool"    -> Tool hackageName'
        _         -> Other
    group' <- do
      groupField <- param' "group"
      customGroupField <- param' "custom-group"
      return $ case groupField of
        "-" -> Nothing
        ""  -> Just customGroupField
        _   -> Just groupField
    -- Modify the item
    -- TODO: actually validate the form and report errors
    --       (don't forget to check that custom-group ≠ "")
    uncache (CacheItemInfo itemId) $ do
      unless (T.null name') $ do
        (edit, _) <- dbUpdate (SetItemName itemId name')
        addEdit edit
      case (T.null link', sanitiseUrl link') of
        (True, _) -> do
            (edit, _) <- dbUpdate (SetItemLink itemId Nothing)
            addEdit edit
        (_, Just l) -> do
            (edit, _) <- dbUpdate (SetItemLink itemId (Just l))
            addEdit edit
        _otherwise ->
            return ()
      do (edit, _) <- dbUpdate (SetItemKind itemId kind')
         addEdit edit
      -- This does all the work of assigning new colors, etc. automatically
      do (edit, _) <- dbUpdate (SetItemGroup itemId group')
         addEdit edit
    -- After all these edits we can render the item
    item <- dbQuery (GetItem itemId)
    category <- dbQuery (GetCategoryByItem itemId)
    lucidIO $ renderItemInfo category item
  -- Item description
  Spock.post (itemVar <//> "description") $ \itemId -> do
    original <- param' "original"
    content' <- param' "content"
    modified <- view (description.mdText) <$> dbQuery (GetItem itemId)
    if modified == original
      then do
        item <- uncache (CacheItemDescription itemId) $ do
          (edit, item) <- dbUpdate (SetItemDescription itemId content')
          addEdit edit
          return item
        lucidIO $ renderItemDescription item
      else do
        setStatus HTTP.status409
        json $ M.fromList [
          ("modified" :: Text, modified),
          ("merged" :: Text, merge original content' modified)]
  -- Item ecosystem
  Spock.post (itemVar <//> "ecosystem") $ \itemId -> do
    original <- param' "original"
    content' <- param' "content"
    modified <- view (ecosystem.mdText) <$> dbQuery (GetItem itemId)
    if modified == original
      then do
        item <- uncache (CacheItemEcosystem itemId) $ do
          (edit, item) <- dbUpdate (SetItemEcosystem itemId content')
          addEdit edit
          return item
        lucidIO $ renderItemEcosystem item
      else do
        setStatus HTTP.status409
        json $ M.fromList [
          ("modified" :: Text, modified),
          ("merged" :: Text, merge original content' modified)]
  -- Item notes
  Spock.post (itemVar <//> "notes") $ \itemId -> do
    original <- param' "original"
    content' <- param' "content"
    modified <- view (notes.mdText) <$> dbQuery (GetItem itemId)
    if modified == original
      then do
        item <- uncache (CacheItemNotes itemId) $ do
          (edit, item) <- dbUpdate (SetItemNotes itemId content')
          addEdit edit
          return item
        category <- dbQuery (GetCategoryByItem itemId)
        lucidIO $ renderItemNotes category item
      else do
        setStatus HTTP.status409
        json $ M.fromList [
          ("modified" :: Text, modified),
          ("merged" :: Text, merge original content' modified)]
  -- Trait
  Spock.post (itemVar <//> traitVar) $ \itemId traitId -> do
    original <- param' "original"
    content' <- param' "content"
    modified <- view (content.mdText) <$> dbQuery (GetTrait itemId traitId)
    if modified == original
      then do
        trait <- uncache (CacheItemTraits itemId) $ do
          (edit, trait) <- dbUpdate (SetTraitContent itemId traitId content')
          addEdit edit
          return trait
        lucidIO $ renderTrait itemId trait
      else do
        setStatus HTTP.status409
        json $ M.fromList [
          ("modified" :: Text, modified),
          ("merged" :: Text, merge original content' modified)]

addMethods :: SpockM () () ServerState ()
addMethods = Spock.subcomponent "add" $ do
  -- New category
  Spock.post "category" $ do
    title' <- param' "content"
    -- If the category exists already, don't create it
    cats <- view categories <$> dbQuery GetGlobalState
    let hasSameTitle cat = T.toCaseFold (cat^.title) == T.toCaseFold title'
    category <- case find hasSameTitle cats of
      Just c  -> return c
      Nothing -> do
        catId <- randomShortUid
        time <- liftIO getCurrentTime
        (edit, newCategory) <- dbUpdate (AddCategory catId title' time)
        invalidateCache' (CacheCategory catId)
        addEdit edit
        return newCategory
    -- And now send the URL of the new (or old) category
    Spock.text ("/haskell/" <> categorySlug category)

  -- New item in a category
  Spock.post (categoryVar <//> "item") $ \catId -> do
    name' <- param' "name"
    -- TODO: do something if the category doesn't exist (e.g. has been
    -- already deleted)
    itemId <- randomShortUid
    -- If the item name looks like a Hackage library, assume it's a Hackage
    -- library.
    let isAllowedChar c = isAscii c && (isAlphaNum c || c == '-')
        looksLikeLibrary = T.all isAllowedChar name'
        kind' = if looksLikeLibrary then Library (Just name') else Other
    time <- liftIO getCurrentTime
    (edit, newItem) <- dbUpdate (AddItem catId itemId name' time kind')
    invalidateCache' (CacheItem itemId)
    addEdit edit
    category <- dbQuery (GetCategory catId)
    lucidIO $ renderItem category newItem
  -- Pro (argument in favor of an item)
  Spock.post (itemVar <//> "pro") $ \itemId -> do
    content' <- param' "content"
    traitId <- randomLongUid
    (edit, newTrait) <- dbUpdate (AddPro itemId traitId content')
    invalidateCache' (CacheItemTraits itemId)
    addEdit edit
    lucidIO $ renderTrait itemId newTrait
  -- Con (argument against an item)
  Spock.post (itemVar <//> "con") $ \itemId -> do
    content' <- param' "content"
    traitId <- randomLongUid
    (edit, newTrait) <- dbUpdate (AddCon itemId traitId content')
    invalidateCache' (CacheItemTraits itemId)
    addEdit edit
    lucidIO $ renderTrait itemId newTrait

otherMethods :: SpockM () () ServerState ()
otherMethods = do
  -- Moving things
  Spock.subcomponent "move" $ do
    -- Move item
    Spock.post itemVar $ \itemId -> do
      direction :: Text <- param' "direction"
      uncache (CacheItem itemId) $ do
        edit <- dbUpdate (MoveItem itemId (direction == "up"))
        addEdit edit
    -- Move trait
    Spock.post (itemVar <//> traitVar) $ \itemId traitId -> do
      direction :: Text <- param' "direction"
      uncache (CacheItemTraits itemId) $ do
        edit <- dbUpdate (MoveTrait itemId traitId (direction == "up"))
        addEdit edit

  -- Deleting things
  Spock.subcomponent "delete" $ do
    -- Delete category
    Spock.post categoryVar $ \catId ->
      uncache (CacheCategory catId) $ do
        mbEdit <- dbUpdate (DeleteCategory catId)
        mapM_ addEdit mbEdit
    -- Delete item
    Spock.post itemVar $ \itemId ->
      uncache (CacheItem itemId) $ do
        mbEdit <- dbUpdate (DeleteItem itemId)
        mapM_ addEdit mbEdit
    -- Delete trait
    Spock.post (itemVar <//> traitVar) $ \itemId traitId ->
      uncache (CacheItemTraits itemId) $ do
        mbEdit <- dbUpdate (DeleteTrait itemId traitId)
        mapM_ addEdit mbEdit

  -- Feeds
  -- TODO: this link shouldn't be absolute [absolute-links]
  baseUrl <- (// "haskell") . _baseUrl <$> getConfig
  Spock.subcomponent "feed" $ do
    -- Feed for items in a category
    Spock.get categoryVar $ \catId -> do
      category <- dbQuery (GetCategory catId)
      let sortedItems = reverse $ sortBy cmp (category^.items)
            where cmp = comparing (^.created) <> comparing (^.uid)
      let route = "feed" <//> categoryVar
      let feedUrl = baseUrl // renderRoute route (category^.uid)
          feedTitle = Atom.TextString (T.unpack (category^.title) ++
                                       " – Haskell – Aelve Guide")
          feedLastUpdate = case sortedItems of
            (item:_) -> Feed.toFeedDateStringUTC Feed.AtomKind (item^.created)
            _        -> ""
      let feedBase = Atom.nullFeed (T.unpack feedUrl) feedTitle feedLastUpdate
      entries <- liftIO $ mapM (itemToFeedEntry baseUrl category) sortedItems
      atomFeed $ feedBase {
        Atom.feedEntries = entries,
        Atom.feedLinks   = [Atom.nullLink (T.unpack feedUrl)] }

adminMethods :: SpockM () () ServerState ()
adminMethods = Spock.subcomponent "admin" $ do
  -- Accept an edit
  Spock.post ("edit" <//> var <//> "accept") $ \n -> do
    dbUpdate (RemovePendingEdit n)
    return ()
  -- Undo an edit
  Spock.post ("edit" <//> var <//> "undo") $ \n -> do
    (edit, _) <- dbQuery (GetEdit n)
    res <- undoEdit edit
    case res of
      Left err -> Spock.text (T.pack err)
      Right () -> do invalidateCacheForEdit edit
                     dbUpdate (RemovePendingEdit n)
                     Spock.text ""
  -- Accept a range of edits
  Spock.post ("edits" <//> var <//> var <//> "accept") $ \m n -> do
    dbUpdate (RemovePendingEdits m n)
  -- Undo a range of edits
  Spock.post ("edits" <//> var <//> var <//> "undo") $ \m n -> do
    edits <- dbQuery (GetEdits m n)
    s <- dbQuery GetGlobalState
    failed <- fmap catMaybes $ for edits $ \(edit, details) -> do
      res <- undoEdit edit
      case res of
        Left err -> return (Just ((edit, details), Just err))
        Right () -> do invalidateCacheForEdit edit
                       dbUpdate (RemovePendingEdit (editId details))
                       return Nothing
    case failed of
      [] -> Spock.text ""
      _  -> lucidIO $ renderEdits s failed
  -- Create a checkpoint
  Spock.post "create-checkpoint" $ do
    db <- _db <$> Spock.getState
    createCheckpoint' db

----------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------

itemToFeedEntry
  :: (MonadIO m)
  => Url -> Category -> Item -> m Atom.Entry
itemToFeedEntry baseUrl category item = do
  entryContent <- Lucid.renderTextT (renderItemForFeed category item)
  return entryBase {
    Atom.entryLinks = [Atom.nullLink (T.unpack entryLink)],
    Atom.entryContent = Just (Atom.HTMLContent (TL.unpack entryContent)) }
  where
    entryLink = baseUrl //
                format "{}#item-{}" (categorySlug category) (item^.uid)
    entryBase = Atom.nullEntry
      (T.unpack (uidToText (item^.uid)))
      (Atom.TextString (T.unpack (item^.name)))
      (Feed.toFeedDateStringUTC Feed.AtomKind (item^.created))
