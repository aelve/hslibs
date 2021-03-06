{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE FlexibleInstances  #-}


-- | Everything concerning rendering and processing Markdown.
--
-- Currently we use the @cmark@ package as the Markdown parser.
module Guide.Markdown
(
  -- * Types
  MarkdownInline(..),
  MarkdownInlineLenses(..),
  MarkdownBlock(..),
  MarkdownBlockLenses(..),
  MarkdownTree(..),
  MarkdownTreeLenses(..),
  Heading(..),

  -- * Converting text to Markdown
  toMarkdownInline,
  toMarkdownBlock,
  toMarkdownTree,

  -- * Misc
  renderMD,
  extractPreface,
  addTargetBlank,
)
where

-- Shared imports
import Imports hiding (some)
-- Parsing
import Text.Megaparsec hiding (State)
import Text.Megaparsec.Char
-- HTML
import Lucid
import Text.HTML.SanitizeXSS
-- Containers
import Data.Tree
-- Markdown
import CMark hiding (Node)
import CMark.Highlight
import CMark.Sections
import ShortcutLinks
import ShortcutLinks.All (hackage)
-- acid-state
import Data.SafeCopy

import Guide.Utils

import qualified CMark as MD
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.Set as S
import qualified Data.Text as T


data MarkdownInline = MarkdownInline {
  markdownInlineSource   :: Text,
  markdownInlineHtml     :: ByteString,
  markdownInlineMarkdown :: ![MD.Node] }
  deriving (Generic, Data, Eq)

data MarkdownBlock = MarkdownBlock {
  markdownBlockSource   :: Text,
  markdownBlockHtml     :: ByteString,
  markdownBlockMarkdown :: ![MD.Node] }
  deriving (Generic, Data, Eq)

data MarkdownTree = MarkdownTree {
  markdownTreeSource    :: Text,
  markdownTreeStructure :: !(Document Text ByteString),
  markdownTreeIdPrefix  :: Text,
  markdownTreeTOC       :: Forest Heading }
  deriving (Generic, Data, Eq)

-- | Table-of-contents heading
data Heading = Heading
    { headingMarkdown :: MarkdownInline
    , headingSlug :: Text
    } deriving (Generic, Data, Eq)

makeClassWithLenses ''MarkdownInline
makeClassWithLenses ''MarkdownBlock
makeClassWithLenses ''MarkdownTree

parseMD :: Text -> [MD.Node]
parseMD s =
  let MD.Node _ DOCUMENT ns =
        highlightNode . shortcutLinks . commonmarkToNode [optSafe] $ s
  in  ns

renderMD :: [MD.Node] -> ByteString
renderMD ns
  -- See https://github.com/jgm/cmark/issues/147
  | any isInlineNode ns
      = toUtf8ByteString
      . sanitize
      . T.concat
      . map (nodeToHtml [] . addTargetBlank)
      $ ns
  | otherwise
      = toUtf8ByteString
      . sanitize
      . nodeToHtml []
      . addTargetBlank
      $ MD.Node Nothing DOCUMENT ns

isInlineNode :: MD.Node -> Bool
isInlineNode (MD.Node _ tp _) = case tp of
  EMPH              -> True
  STRONG            -> True
  LINK _ _          -> True
  IMAGE _ _         -> True
  CUSTOM_INLINE _ _ -> True
  SOFTBREAK         -> True
  LINEBREAK         -> True
  TEXT _            -> True
  CODE _            -> True
  HTML_INLINE _     -> True
  _other            -> False

-- | Convert a Markdown structure to a string with formatting removed.
stringify :: [MD.Node] -> Text
stringify = T.concat . map go
  where
    go (MD.Node _ tp ns) = case tp of
      DOCUMENT          -> stringify ns
      THEMATIC_BREAK    -> stringify ns
      PARAGRAPH         -> stringify ns
      BLOCK_QUOTE       -> stringify ns
      CUSTOM_BLOCK _ _  -> stringify ns
      HEADING _         -> stringify ns
      LIST _            -> stringify ns
      ITEM              -> stringify ns
      EMPH              -> stringify ns
      STRONG            -> stringify ns
      LINK _ _          -> stringify ns
      IMAGE _ _         -> stringify ns
      CUSTOM_INLINE _ _ -> stringify ns
      CODE         xs   -> xs
      CODE_BLOCK _ xs   -> xs
      TEXT         xs   -> xs
      SOFTBREAK         -> " "
      LINEBREAK         -> " "
      HTML_BLOCK _      -> ""
      HTML_INLINE _     -> ""

-- | Extract everything before the first heading.
--
-- Note that if you render 'markdownBlockSource' of the produced Markdown
-- block, it won't necessarily parse into 'markdownBlockHtml' from the same
-- block. It's because rendered Markdown might depend on links that are
-- defined further in the tree.
extractPreface :: MarkdownTree -> MarkdownBlock
extractPreface = mkBlock . preface . markdownTreeStructure
  where
    mkBlock x = MarkdownBlock {
      markdownBlockSource   = getSource x,
      markdownBlockHtml     = renderMD (stripSource x),
      markdownBlockMarkdown = stripSource x }

-- | Flatten Markdown by concatenating all block elements.
extractInlines :: [MD.Node] -> [MD.Node]
extractInlines = concatMap go
  where
    go node@(MD.Node _ tp ns) = case tp of
      -- Block containers
      DOCUMENT          -> extractInlines ns
      BLOCK_QUOTE       -> extractInlines ns
      CUSTOM_BLOCK _ _  -> extractInlines ns
      LIST _            -> extractInlines ns
      ITEM              -> extractInlines ns
      -- Inline containers
      PARAGRAPH         -> ns
      HEADING _         -> ns
      IMAGE _ _         -> ns
      -- Inlines
      EMPH              -> [node]
      STRONG            -> [node]
      LINK _ _          -> [node]
      CUSTOM_INLINE _ _ -> [node]
      SOFTBREAK         -> [node]
      LINEBREAK         -> [node]
      TEXT _            -> [node]
      CODE _            -> [node]
      -- Other stuff
      THEMATIC_BREAK    -> []
      HTML_BLOCK xs     -> [MD.Node Nothing (CODE xs) []]
      HTML_INLINE xs    -> [MD.Node Nothing (CODE xs) []]
      CODE_BLOCK _ xs   -> [MD.Node Nothing (CODE xs) []]

-- | Convert 'LINK' to 'HTML_INLINE' with @target="_blank"@ attribute added.
--
-- It will cause the link to be opened in a new tab, which is the behavior
-- we want for links in user-submitted content.
addTargetBlank :: MD.Node -> MD.Node
addTargetBlank (MD.Node pos (LINK url title) ns) =
    MD.Node pos (HTML_INLINE blankLink) []
  where
    blankLink = toText $ renderText
      $ a_ ([href_ url, target_ "_blank"] ++ [title_ title | title /= ""])
      $ toHtmlRaw $ renderMD ns
addTargetBlank (MD.Node pos tp ns) = MD.Node pos tp (map addTargetBlank ns)

shortcutLinks :: MD.Node -> MD.Node
shortcutLinks node@(MD.Node pos (LINK url title) ns) | "@" <- T.take 1 url =
  -- %20s are possibly introduced by cmark (Pandoc definitely adds them,
  -- no idea about cmark but better safe than sorry) and so they need to
  -- be converted back to spaces
  case parseLink (T.replace "%20" " " url) of
    Left _err -> MD.Node pos (LINK url title) (map shortcutLinks ns)
    Right (shortcut, opt, text) -> do
      let text' = fromMaybe (stringify [node]) text
      let shortcuts = (["hk"], hackage) : allShortcuts
      case useShortcutFrom shortcuts shortcut opt text' of
        Success link ->
          MD.Node pos (LINK link title) (map shortcutLinks ns)
        Warning warnings link ->
          let warningText = "[warnings when processing shortcut link: " <>
                            toText (intercalate ", " warnings) <> "]"
              warningNode = MD.Node Nothing (TEXT warningText) []
          in  MD.Node pos (LINK link title)
                             (warningNode : map shortcutLinks ns)
        Failure err ->
          let errorText = "[error when processing shortcut link: " <>
                          toText err <> "]"
          in  MD.Node Nothing (TEXT errorText) []
shortcutLinks (MD.Node pos tp ns) =
  MD.Node pos tp (map shortcutLinks ns)

-- TODO: this should be in the shortcut-links package itself

-- | Parse a shortcut link. Allowed formats:
--
-- @
-- \@name
-- \@name:text
-- \@name(option)
-- \@name(option):text
-- @
parseLink :: Text -> Either String (Text, Maybe Text, Maybe Text)
parseLink = either (Left . show) Right . parse p ""
  where
    shortcut = some (alphaNumChar <|> char '-')
    opt      = char '(' *> some (noneOf [')']) <* char ')'
    text     = char ':' *> some anyChar
    p :: Parsec Void Text (Text, Maybe Text, Maybe Text)
    p = do
      _ <- char '@'
      (,,) <$> (toText <$> shortcut)
           <*> optional (toText <$> opt)
           <*> optional (toText <$> text)

toMarkdownInline :: Text -> MarkdownInline
toMarkdownInline s = MarkdownInline {
  markdownInlineSource   = s,
  markdownInlineHtml     = html,
  markdownInlineMarkdown = inlines }
  where
    inlines = extractInlines (parseMD s)
    html = renderMD inlines

toMarkdownBlock :: Text -> MarkdownBlock
toMarkdownBlock s = MarkdownBlock {
  markdownBlockSource   = s,
  markdownBlockHtml     = html,
  markdownBlockMarkdown = doc }
  where
    doc = parseMD s
    html = renderMD doc

toMarkdownTree :: Text -> Text -> MarkdownTree
toMarkdownTree idPrefix s = MarkdownTree {
  markdownTreeSource    = s,
  markdownTreeIdPrefix  = idPrefix,
  markdownTreeStructure = tree,
  markdownTreeTOC       = toc }
  where
    blocks :: [MD.Node]
    blocks = parseMD s
    --
    slugify :: Text -> Text
    slugify x = idPrefix <> makeSlug x
    --
    tree :: Document Text ByteString
    tree = renderContents . slugifyDocument slugify $
             nodesToDocument (WithSource s blocks)
    --
    toc :: Forest Heading
    toc = sections tree
            & each.each
            %~ (\Section{..} -> Heading (nodesToMdInline heading) headingAnn)

    nodesToMdInline :: WithSource [MD.Node] -> MarkdownInline
    nodesToMdInline (WithSource src nodes) = MarkdownInline
        { markdownInlineSource   = src
        , markdownInlineHtml     = html
        , markdownInlineMarkdown = inlines
        }
      where
        inlines = extractInlines nodes
        html = renderMD inlines

renderContents :: Document a b -> Document a ByteString
renderContents doc = doc {
  prefaceAnn = renderMD (stripSource (preface doc)),
  sections = over (each.each) renderSection (sections doc) }
  where
    renderSection sec = sec {
      contentAnn = renderMD (stripSource (content sec)) }

slugifyDocument :: (Text -> Text) -> Document a b -> Document Text b
slugifyDocument slugify doc = doc {
  sections = evalState ((each.each) process (sections doc)) mempty }
  where
    process :: Section a b -> State (Set Text) (Section Text b)
    process sec = do
      previousIds <- get
      let slug = until (`S.notMember` previousIds) (<> "_")
                   (slugify (stringify (stripSource (heading sec))))
      modify (S.insert slug)
      return sec{headingAnn = slug}

instance Show MarkdownInline where
  show = show . markdownInlineSource
instance Show MarkdownBlock where
  show = show . markdownBlockSource
instance Show MarkdownTree where
  show = show . markdownTreeSource
deriving instance Show Heading

instance Aeson.ToJSON MarkdownInline where
  toJSON md = Aeson.object [
    "text" Aeson..= markdownInlineSource md,
    "html" Aeson..= utf8ToText (markdownInlineHtml md) ]
instance Aeson.ToJSON MarkdownBlock where
  toJSON md = Aeson.object [
    "text" Aeson..= markdownBlockSource md,
    "html" Aeson..= utf8ToText (markdownBlockHtml md) ]
instance Aeson.ToJSON MarkdownTree where
  toJSON md = Aeson.object [
    "text" Aeson..= markdownTreeSource md ]

instance ToHtml MarkdownInline where
  toHtmlRaw = toHtml
  toHtml    = toHtmlRaw . markdownInlineHtml
instance ToHtml MarkdownBlock where
  toHtmlRaw = toHtml
  toHtml    = toHtmlRaw . markdownBlockHtml
instance ToHtml MarkdownTree where
  toHtmlRaw = toHtml
  toHtml    = toHtmlRaw . renderDoc . markdownTreeStructure
    where
      renderDoc Document{..} = BS.concat $
        prefaceAnn :
        map renderSection (concatMap flatten sections)
      renderSection Section{..} = toByteString . renderBS $ do
        mkH $ do
          span_ [id_ headingAnn] ""
          toHtmlRaw (renderMD (stripSource heading))
        toHtmlRaw contentAnn
        where
          mkH = case level of
            1 -> h1_; 2 -> h2_; 3 -> h3_;
            4 -> h4_; 5 -> h5_; 6 -> h6_;
            _other -> error "Markdown.toHtml: level > 6"

instance SafeCopy MarkdownInline where
  version = 0
  kind = base
  putCopy = contain . safePut . markdownInlineSource
  getCopy = contain $ toMarkdownInline <$> safeGet
instance SafeCopy MarkdownBlock where
  version = 0
  kind = base
  putCopy = contain . safePut . markdownBlockSource
  getCopy = contain $ toMarkdownBlock <$> safeGet
instance SafeCopy MarkdownTree where
  version = 0
  kind = base
  putCopy md = contain $ do
    safePut (markdownTreeIdPrefix md)
    safePut (markdownTreeSource md)
  getCopy = contain $
    toMarkdownTree <$> safeGet <*> safeGet
