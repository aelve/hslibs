<template>
<!-- Wrapper div is required for correct destroying of component
     cause easyMDE adds new html elements next to textarea -->
<div
  class="elevation-2"
  @keydown.ctrl.enter="save"
>
  <textarea ref="editor" />
  <v-toolbar
    flat
    height="30"
    color="#e5e5e5"
    class="pa-2 markdown-editor-bottom-toolbar"
    v-if="editor"
  >
    <v-toolbar-items>
      <v-btn
        small
        class="mr-2 text-transform-none"
        @click="save"
      >
        Save
      </v-btn>
      <v-btn
        small
        class="text-transform-none"
        @click="cancel"
      >
        Cancel
      </v-btn>
    </v-toolbar-items>
    or press Ctrl+Enter to save
  </v-toolbar>
</div>
</template>

<script lang="ts">
import 'easymde/dist/easymde.min.css'
import { Vue, Component, Prop, Watch } from 'vue-property-decorator'

@Component
export default class MarkdownEditor extends Vue {
  @Prop({
    type: String,
    default: ''
  }) value: string

  @Watch('value')
  onValueChange (newVal: string): void {
    if (!this.editor || this.editor.value() === newVal) {
      return
    }
    this.editor.value(newVal)
  }

  editor: object = null

  async mounted () {
    const EasyMDE = (await import('easymde')).default
    this.editor = new EasyMDE({
      element: this.$refs.editor,
      autofocus: true,
      initialValue: this.value,
      spellChecker: false,
      status: false,
      toolbar: [
        'bold',
        'italic',
        'strikethrough',
        'code',
        'quote',
        'heading',
        'heading-smaller',
        'heading-bigger',
        '|',
        'unordered-list',
        'ordered-list',
        '|',
        'link',
        'image',
        'horizontal-rule',
        '|',
        'clean-block',
        '|',
        'preview',
        'side-by-side',
        'fullscreen',
        {
          name: 'guide',
          action () {
            window.open('https://commonmark.org/help/', '_blank')
          },
          className: 'fa fa-question-circle',
          title: 'Markdown Guide',
        },
      ]
    })
    this.editor.codemirror.on('change', () => {
      this.$emit('input', this.editor.value())
    })
  }

  save () {
    this.$emit('save', this.editor.value())
  }

  cancel () {
    this.$emit('cancel')
  }
}
</script>

<style scoped>
/* .markdown-editor {
  border: 1px solid #bbb;
} */
>>> .editor-toolbar,
>>> .CodeMirror {
  border: none;
  border-radius: 0;
  border-bottom: 1px solid #bbb;
}
>>> .CodeMirror {
  height: 300px;
}
>>> .v-toolbar__content {
  padding-left: 0;
}
</style>