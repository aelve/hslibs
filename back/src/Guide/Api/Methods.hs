{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE TypeOperators     #-}

module Guide.Api.Methods where


import Imports

import Data.Acid as Acid
import Data.Aeson (encode)
import Data.Text (Text)
import Servant

import Guide.Api.Types
import Guide.Api.Utils
import Guide.Diff (merge)
import Guide.Markdown (MarkdownBlock (..), MarkdownInline (..), MarkdownTree (..))
import Guide.State
import Guide.Types
import Guide.Utils
import Guide.Api.Guider (Guider)

import qualified Data.Set as S
import qualified Data.Text as T
import qualified Guide.Search as Search

----------------------------------------------------------------------------
-- Categories
----------------------------------------------------------------------------

-- | Get a list of available categories.
getCategories :: DB -> Guider [CCategoryInfo]
getCategories db = do
  dbQuery db GetCategories <&> \xs ->
    map toCCategoryInfo xs

-- | Get a single category and all of its items.
getCategory :: DB -> Uid Category -> Guider CCategoryFull
getCategory db catId = toCCategoryFull <$> getCategoryOrFail db catId

-- | Create a new category, given the title and the grandparent (aka group).
--
-- Returns the ID of the created category (or of the existing one if the
-- category with this title exists already).
createCategory :: DB -> Text -> Text -> Guider (Uid Category)
createCategory db title' group' = do
  when (T.null title') $ throwError err400{errBody = "Title not provided"}
  when (T.null group') $ throwError err400{errBody = "Group' not provided"}
  -- If the category exists already, don't create it
  cats <- view categories <$> dbQuery db GetGlobalState
  let isDuplicate cat = T.toCaseFold (cat^.title) == T.toCaseFold title'
        && T.toCaseFold (cat^.group_) == T.toCaseFold group'
  case find isDuplicate cats of
    Just c  -> return (c^.uid)
    Nothing -> do
      catId <- randomShortUid
      time <- liftIO getCurrentTime
      (_edit, _newCategory) <- dbUpdate db (AddCategory catId title' group' time)
      -- TODO addEdit edit
      return catId

-- | Edit categoty's note.
setCategoryNotes :: DB -> Uid Category -> CTextEdit -> Guider NoContent
setCategoryNotes db catId CTextEdit{..} = do
  serverModified <- markdownBlockMdSource . _categoryNotes <$> getCategoryOrFail db catId
  checkConflict CTextEdit{..} serverModified
  _ <- dbUpdate db (SetCategoryNotes catId $ unH cteModified)
  pure NoContent

-- | Edit category's info (title, group, status, sections (pro/con, ecosystem, note)).
setCategoryInfo :: DB -> Uid Category -> CCategoryInfoEdit -> Guider NoContent
setCategoryInfo db catId CCategoryInfoEdit{..} = do
  category <- getCategoryOrFail db catId
  -- TODO diff and merge
  _ <- dbUpdate db $ SetCategoryTitle catId $ unH ccieTitle
  _ <- dbUpdate db $ SetCategoryGroup catId $ unH ccieGroup
  _ <- dbUpdate db $ SetCategoryStatus catId $ unH ccieStatus
  let oldEnabledSections = category ^. enabledSections
  let newEnabledSections = unH ccieSections
  _ <- dbUpdate db $ ChangeCategoryEnabledSections catId
      (newEnabledSections S.\\ oldEnabledSections)
      (oldEnabledSections S.\\ newEnabledSections)
  -- TODO record edits
  pure NoContent

-- | Delete a category.
deleteCategory :: DB -> Uid Category -> Guider NoContent
deleteCategory db catId = do
  _ <- getCategoryOrFail db catId
  _mbEdit <- dbUpdate db (DeleteCategory catId)
  pure NoContent
  -- TODO mapM_ addEdit mbEdit

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------

-- | Create a new item, given the name.
--
-- Returns the ID of the created item. Unlike 'createCategory', allows items
-- with duplicated names.
createItem :: DB -> Uid Category -> Text -> Guider (Uid Item)
createItem db catId name' = do
  _ <- getCategoryOrFail db catId
  when (T.null name') $ throwError err400{errBody = "Name not provided"}
  itemId <- randomShortUid
  -- If the item name looks like a Hackage library, assume it's a Hackage
  -- library.
  let isAllowedChar c = isAscii c && (isAlphaNum c || c == '-')
      looksLikeLibrary = T.all isAllowedChar name'
      kind' = if looksLikeLibrary then Library (Just name') else Other
  time <- liftIO getCurrentTime
  (_edit, _newItem) <- dbUpdate db (AddItem catId itemId name' time kind')
  -- TODO: addEdit edit
  pure itemId

-- TODO: move an item

-- | Set item's info
setItemInfo :: DB -> Uid Item -> CItemInfo -> Guider NoContent
setItemInfo db itemId CItemInfo{..} = do
  _ <- getItemOrFail db itemId
  -- TODO diff and merge
  _ <- dbUpdate db $ SetItemName itemId $ unH ciiName
  _ <- dbUpdate db $ SetItemGroup itemId $ unH ciiGroup
  _ <- dbUpdate db $ SetItemLink itemId $ unH ciiLink
  _ <- dbUpdate db $ SetItemKind itemId $ unH ciiKind
  pure NoContent

-- | Set item's summary.
setItemSummary :: DB -> Uid Item -> CTextEdit -> Guider NoContent
setItemSummary db itemId CTextEdit{..} = do
  serverModified <- markdownBlockMdSource . _itemDescription <$> getItemOrFail db itemId
  checkConflict CTextEdit{..} serverModified
  (_edit, _newItem) <- dbUpdate db (SetItemDescription itemId $ unH cteModified)
  pure NoContent

-- | Set item's ecosystem.
setItemEcosystem :: DB -> Uid Item -> CTextEdit -> Guider NoContent
setItemEcosystem db itemId CTextEdit{..} = do
  serverModified <- markdownBlockMdSource . _itemEcosystem <$> getItemOrFail db itemId
  checkConflict CTextEdit{..} serverModified
  (_edit, _newItem) <- dbUpdate db (SetItemEcosystem itemId $ unH cteModified)
  pure NoContent

-- | Set item's notes.
setItemNotes :: DB -> Uid Item -> CTextEdit -> Guider NoContent
setItemNotes db itemId CTextEdit{..} = do
  serverModified <- markdownTreeMdSource . _itemNotes <$> getItemOrFail db itemId
  checkConflict CTextEdit{..} serverModified
  (_edit, _newItem) <- dbUpdate db (SetItemNotes itemId $ unH cteModified)
  pure NoContent

-- | Delete an item.
deleteItem :: DB -> Uid Item -> Guider NoContent
deleteItem db itemId = do
  _mbEdit <- dbUpdate db (DeleteItem itemId)
  pure NoContent
  -- TODO: mapM_ addEdit mbEdit

----------------------------------------------------------------------------
-- Traits
----------------------------------------------------------------------------

-- TODO: move a trait

-- | Create a trait (pro/con).
createTrait :: DB -> Uid Item -> TraitType -> Text -> Guider (Uid Trait)
createTrait db itemId traitType text = do
  when (T.null text) $ throwError err400{errBody = "Trait text not provided"}
  traitId <- randomShortUid
  (_edit, _newTrait) <- case traitType of
    Con -> dbUpdate db (AddCon itemId traitId text)
    Pro -> dbUpdate db (AddPro itemId traitId text)
  -- TODO: mapM_ addEdit mbEdit
  pure traitId

-- | Update the text of a trait (pro/con).
setTrait :: DB -> Uid Item -> Uid Trait -> CTextEdit -> Guider NoContent
setTrait db itemId traitId CTextEdit{..} = do
  serverModified <- markdownInlineMdSource . _traitContent <$> getTraitOrFail db itemId traitId
  checkConflict CTextEdit{..} serverModified
  (_edit, _newCategory) <- dbUpdate db (SetTraitContent itemId traitId $ unH cteModified)
  pure NoContent

-- | Delete a trait (pro/con).
deleteTrait :: DB -> Uid Item -> Uid Trait -> Guider NoContent
deleteTrait db itemId traitId = do
  _mbEdit <- dbUpdate db (DeleteTrait itemId traitId)
  pure NoContent


----------------------------------------------------------------------------
-- Search
----------------------------------------------------------------------------

-- | Site-wide search.
--
-- Returns at most 100 results.
search :: DB -> Text -> Guider [CSearchResult]
search db searchQuery = do
  gs <- dbQuery db GetGlobalState
  pure $ map toCSearchResult $ take 100 $ Search.search searchQuery gs

----------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------

-- | Update something in the database.
dbUpdate :: (MonadIO m, EventState event ~ GlobalState, UpdateEvent event)
         => DB -> event -> m (EventResult event)
dbUpdate db x = liftIO $ do
  Acid.update db SetDirty
  Acid.update db x

-- | Read something from the database.
dbQuery :: (MonadIO m, EventState event ~ GlobalState, QueryEvent event)
        => DB -> event -> m (EventResult event)
dbQuery db x = liftIO $
  Acid.query db x

-- | Helper. Get a category from database and throw error 404 when it doesn't exist.
getCategoryOrFail :: DB -> Uid Category -> Guider Category
getCategoryOrFail db catId = do
  dbQuery db (GetCategoryMaybe catId) >>= \case
    Nothing  -> throwError $ err404 {errBody = "Category not found"}
    Just cat -> pure cat

-- | Helper. Get an item from database and throw error 404 when the item doesn't exist.
getItemOrFail :: DB -> Uid Item -> Guider Item
getItemOrFail db itemId = do
  dbQuery db (GetItemMaybe itemId) >>= \case
    Nothing  -> throwError $ err404 {errBody = "Item not found"}
    Just item -> pure item

-- | Helper. Get a trait from database and throw error 404 when
-- either the item or the trait doesn't exist.
getTraitOrFail :: DB -> Uid Item -> Uid Trait -> Guider Trait
getTraitOrFail db itemId traitId = do
  dbQuery db (GetItemMaybe itemId) >>= \case
    Nothing  -> throwError $ err404 {errBody = "Item not found"}
    Just _ -> do
      dbQuery db (GetTraitMaybe itemId traitId) >>= \case
        Nothing -> throwError $ err404 {errBody = "Trait not found"}
        Just trait -> pure trait

-- | Checker. When states of database before and after editing is different, fail with a conflict data.
checkConflict :: CTextEdit -> Text -> Guider ()
checkConflict CTextEdit{..} serverModified = do
  let original = unH cteOriginal
  let modified = unH cteModified
  when (original /= serverModified) $ do
    let merged = merge original modified serverModified
    let conflict = CMergeConflict
          { cmcOriginal = cteOriginal
          , cmcModified = cteModified
          , cmcServerModified = H serverModified
          , cmcMerged = H merged
          }
    throwError $ err409 {errBody = encode conflict}