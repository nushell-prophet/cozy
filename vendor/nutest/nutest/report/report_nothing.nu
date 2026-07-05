
export def create []: any -> record<name: string, save: closure> {
    {
        name: "report nothing"
        save: { || ignore }
    }
}
